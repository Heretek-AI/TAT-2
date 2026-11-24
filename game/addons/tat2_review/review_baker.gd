extends RefCounted
## Headless review-map baker. The CLI wrapper is tools/bake_review_map.gd; this
## class lives under res:// so the same code is callable from tests and the
## editor dock.
##
## One real LevelLoader call per sublevel builds a container named after the
## .tatlevel.json stem. That container is the ancestry the review tags use:
## LevelLoader itself does not record a source sublevel on its nodes, so a
## per-sublevel load is the only honest way to attribute geometry without
## editing the loader (owned by another worker).
##
## Outputs, under `<out>/`:
##   <Sublevel>.scn   binary PackedScene per sublevel (required path)
##   world.scn        assembly of the per-sublevel scenes (no bookmarks)
##   review.tscn      master: per-sublevel instances + bookmarks + environment
##   review_manifest.json
##
## `world.scn`/review.tscn instance the per-sublevel scenes instead of packing
## geometry twice; the manifest records `world_mode = "assembly"`. A single
## combined-loader world bake is not implemented: it would duplicate every mesh
## resource into one file (and can exceed practical scene sizes).

const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")
const Tagger: GDScript = preload("res://addons/tat2_review/review_tagger.gd")
const MapData: GDScript = preload("res://addons/tat2_review/review_map_data.gd")

const WORLD_SKIP_BYTES: int = 150 * 1024 * 1024
const MAX_LIGHTS: int = 160
const REVIEW_FOV: float = 54.54

var _log: Array[String] = []


func log_lines() -> Array[String]:
	return _log


## Runs the whole bake. Returns a JSON-safe report dictionary with `ok`.
func bake(tree: SceneTree, map_id: String, out_dir: String, opts: Dictionary = {}) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var report: Dictionary = {
		"ok": false,
		"map": map_id,
		"out_dir": out_dir,
		"git_sha": _git_sha(),
		"seed": int(opts.get("seed", 0)),
		"world_mode": "assembly",
		"resolution": {},
		"sublevels": [],
		"totals": {},
		"issues": {},
		"bookmarks": [],
		"scenes": [],
		"checks": {},
		"warnings": [],
		"errors": [],
		"bake_ms": 0,
	}
	var resolved: Dictionary = MapData.resolve_sublevels(map_id, int(opts.get("contract_order", 0)))
	report["resolution"] = {
		"source": resolved.get("source", ""),
		"contract_order": int(resolved.get("contract_order", 0)),
		"path_count": (resolved.get("paths", []) as Array).size(),
		"warning": resolved.get("warning", ""),
	}
	var paths: Array = resolved.get("paths", [])
	if paths.is_empty():
		report["errors"] = ["no sublevels resolved for map '%s'" % map_id]
		_append_log("error=no_sublevels map=%s" % map_id)
		return report

	var abs_out: String = _globalize(out_dir)
	var mk_err: int = DirAccess.make_dir_recursive_absolute(abs_out)
	if mk_err != OK and not DirAccess.dir_exists_absolute(abs_out):
		report["errors"] = ["cannot create out dir %s (err=%d)" % [abs_out, mk_err]]
		return report

	var staging: Node3D = Node3D.new()
	staging.name = "ReviewBakeStaging"
	tree.root.add_child(staging)
	var loader: Node = LevelLoaderScript.new()
	loader.name = "ReviewLevelLoader"
	staging.add_child(loader)
	await tree.process_frame

	var sub_scenes: Array[Dictionary] = []
	var totals: Dictionary = _empty_totals()
	var all_issues: Dictionary = {}
	var all_errors: Array[String] = []
	var all_warnings: Array[String] = []
	var max_lights: int = int(opts.get("max_lights", MAX_LIGHTS))
	var pack_failed: bool = false

	for path_v: Variant in paths:
		var json_path: String = str(path_v)
		if not FileAccess.file_exists(json_path):
			all_errors.append("missing sublevel: %s" % json_path)
			continue
		var stem: String = json_path.get_file().trim_suffix(".tatlevel.json")
		var container: Node3D = Node3D.new()
		container.name = stem
		container.set_meta("review_sublevel", stem)
		container.set_meta("review_kind", "group")
		staging.add_child(container)
		_append_log("Load sublevel " + stem)
		var sub_started: int = Time.get_ticks_msec()
		var res_v: Variant = await loader.call("load_sublevels_async", [json_path], container, null, max_lights, true)
		var res: Dictionary = res_v if res_v is Dictionary else {}
		var loader_ms: int = Time.get_ticks_msec() - sub_started
		Tagger.apply_tags(container, stem)
		_name_review_nodes(container)
		var stats: Dictionary = Tagger.collect_stats(container)
		_accumulate_totals(totals, stats, res)
		for issue: String in (stats["issues"] as Dictionary).keys():
			all_issues[issue] = int(all_issues.get(issue, 0)) + int((stats["issues"] as Dictionary)[issue])
		var entry: Dictionary = {
			"sublevel": stem,
			"json": json_path,
			"loader_ms": loader_ms,
			"loader_counts": _pick_loader_counts(res),
			"node_counts": {
				"nodes": int(stats["nodes"]),
				"kinds": stats["kinds"],
				"issues": stats["issues"],
				"roles": stats["roles"],
				"instances": int(stats["instances"]),
				"draw_instances": int(stats["draw_instances"]),
				"surfaces": int(stats["surfaces"]),
			},
			"aabb": _aabb_to_dict(stats),
			"scene": "",
			"scene_bytes": 0,
			"checks": _consistency_checks(res, stats),
		}
		report["checks"][stem] = entry["checks"]
		for check_name: String in (entry["checks"] as Dictionary).keys():
			if not bool((entry["checks"] as Dictionary)[check_name].get("ok", false)):
				all_errors.append("consistency %s.%s: %s" % [stem, check_name, str((entry["checks"] as Dictionary)[check_name])])

		# Save the sublevel. Nodes must be owned by the container for
		# PackedScene.pack(); the loader leaves owner null on runtime children.
		_set_owner_recursive(container, container)
		var packed: PackedScene = PackedScene.new()
		var pack_err: int = packed.pack(container)
		if pack_err != OK:
			all_errors.append("pack failed for %s (err=%d)" % [stem, pack_err])
			pack_failed = true
		else:
			var scene_path: String = out_dir.path_join(stem + ".scn")
			var save_err: int = ResourceSaver.save(packed, scene_path)
			if save_err != OK:
				all_errors.append("save failed for %s (err=%d)" % [scene_path, save_err])
				pack_failed = true
			else:
				entry["scene"] = scene_path
				entry["scene_bytes"] = _file_size(scene_path)
				sub_scenes.append(entry)
				report["scenes"].append({"path": scene_path, "bytes": entry["scene_bytes"], "kind": "sublevel"})
		report["sublevels"].append(entry)
		staging.remove_child(container)
		container.free()
		_append_log("  built %s in %d ms (%d bytes)" % [stem, loader_ms, int(entry["scene_bytes"])])

	report["totals"] = totals
	report["issues"] = all_issues
	report["seed"] = int(opts.get("seed", 0))
	report["bookmarks"] = _bookmarks_for_manifest(map_id)

	# Per-sublevel scenes are the required output. If any one failed to pack,
	# stop before writing the assembly so a partial world cannot be mistaken
	# for a complete one.
	if pack_failed or not all_errors.is_empty():
		report["errors"] = all_errors
		report["warnings"] = all_warnings
		report["bake_ms"] = Time.get_ticks_msec() - started
		staging.queue_free()
		return report

	# world.scn: plain assembly (instances only, no environment/bookmarks).
	var world_res: Dictionary = _save_assembly(tree, out_dir, sub_scenes, false, map_id)
	if not bool(world_res.get("ok", false)):
		report["errors"].append(str(world_res.get("error", "world assembly failed")))
	else:
		report["scenes"].append({"path": world_res["path"], "bytes": world_res["bytes"], "kind": "world"})
		report["world_mode"] = "assembly"
	# review.tscn: assembly + bookmarks + review environment + camera.
	var master_res: Dictionary = _save_assembly(tree, out_dir, sub_scenes, true, map_id)
	if not bool(master_res.get("ok", false)):
		report["errors"].append(str(master_res.get("error", "review master failed")))
	else:
		report["scenes"].append({"path": master_res["path"], "bytes": master_res["bytes"], "kind": "review_master"})

	report["warnings"] = all_warnings
	report["errors"] = all_errors
	report["bake_ms"] = Time.get_ticks_msec() - started
	report["ok"] = all_errors.is_empty() and not pack_failed and bool(world_res.get("ok", false)) and bool(master_res.get("ok", false))
	staging.queue_free()
	return report


func write_manifest(report: Dictionary, out_dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(_globalize(out_dir))
	var path: String = out_dir.path_join("review_manifest.json")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(report, "  ") + "\n")
	f.close()
	return OK


func _save_assembly(tree: SceneTree, out_dir: String, sub_scenes: Array[Dictionary], with_master_extras: bool, map_id: String) -> Dictionary:
	var root: Node3D = Node3D.new()
	root.name = "ReviewMaster" if with_master_extras else "ReviewWorld"
	root.set_meta("review_map", map_id)
	root.set_meta("review_kind", "group")
	root.set_meta("review_generated_by", "tools/bake_review_map.gd")
	if with_master_extras:
		root.set_meta("review_toggles", _default_toggles())
	tree.root.add_child(root)
	for entry: Dictionary in sub_scenes:
		var scene_path: String = str(entry.get("scene", ""))
		if scene_path == "":
			continue
		var ps: PackedScene = load(scene_path) as PackedScene
		if ps == null:
			root.free()
			return {"ok": false, "error": "cannot reload baked scene %s" % scene_path}
		var inst: Node3D = ps.instantiate() as Node3D
		if inst == null:
			root.free()
			return {"ok": false, "error": "baked scene %s is not Node3D" % scene_path}
		inst.name = str(entry.get("sublevel", inst.name))
		root.add_child(inst)
		inst.owner = root
		# The instance root already carries review_sublevel from the bake; keep
		# it authoritative and do not recurse (children belong to the instance).
	if with_master_extras:
		_add_review_environment(root, map_id)
		_add_bookmarks(root, map_id)
		_add_camera(root, map_id)
	var packed: PackedScene = PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err != OK:
		root.queue_free()
		return {"ok": false, "error": "pack failed for assembly (err=%d)" % pack_err}
	var fname: String = "review.tscn" if with_master_extras else "world.scn"
	var path: String = out_dir.path_join(fname)
	var save_err: int = ResourceSaver.save(packed, path)
	var bytes: int = _file_size(path) if save_err == OK else 0
	root.queue_free()
	if save_err != OK:
		return {"ok": false, "error": "save failed for %s (err=%d)" % [path, save_err]}
	if bytes > WORLD_SKIP_BYTES:
		DirAccess.remove_absolute(_globalize(path))
		return {"ok": false, "error": "%s exceeded %d bytes (%.1f MB) and was removed" % [fname, WORLD_SKIP_BYTES, bytes / 1048576.0]}
	return {"ok": true, "path": path, "bytes": bytes}


func _add_review_environment(root: Node3D, map_id: String) -> void:
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.012, 0.02, 0.05)
	sky_mat.sky_horizon_color = Color(0.06, 0.08, 0.14)
	sky_mat.ground_bottom_color = Color(0.01, 0.012, 0.02)
	sky_mat.ground_horizon_color = Color(0.05, 0.06, 0.10)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.35
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "ReviewEnvironment"
	we.environment = env
	we.set_meta("review_kind", "environment")
	we.set_meta("review_added", true)
	root.add_child(we)
	we.owner = root

	var moon: DirectionalLight3D = DirectionalLight3D.new()
	moon.name = "ReviewMoon"
	moon.light_energy = 0.22
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	moon.set_meta("review_kind", "light")
	moon.set_meta("review_added", true)
	root.add_child(moon)
	moon.owner = root


func _add_bookmarks(root: Node3D, map_id: String) -> void:
	var marks: Array = MapData.bookmarks_for(map_id)
	for i: int in range(marks.size()):
		var b: Dictionary = marks[i]
		var marker: Marker3D = Marker3D.new()
		marker.name = "BM_%d_%s" % [i + 1, str(b.get("name", "bookmark"))]
		marker.position = b.get("pos", Vector3.ZERO)
		marker.set_meta("review_kind", "bookmark")
		marker.set_meta("review_bookmark", str(b.get("name", "")))
		marker.set_meta("review_source", str(b.get("source", "")))
		var target: Vector3 = b.get("target", marker.position + Vector3(0, 0, -5))
		marker.set_meta("review_target", target)
		root.add_child(marker)
		marker.owner = root


func _add_camera(root: Node3D, map_id: String) -> void:
	var marks: Array = MapData.bookmarks_for(map_id)
	if marks.is_empty():
		return
	var first: Dictionary = marks[0]
	var cam: Camera3D = Camera3D.new()
	cam.name = "ReviewCamera"
	cam.fov = REVIEW_FOV
	cam.position = first.get("pos", Vector3.ZERO)
	cam.set_meta("review_kind", "camera")
	cam.set_meta("review_added", true)
	root.add_child(cam)
	cam.owner = root
	cam.look_at(first.get("target", cam.position + Vector3(0, 0, -5)))
	cam.current = true


func _default_toggles() -> Dictionary:
	return {
		"Periphery": true,
		"POI": true,
		"Gameplay": true,
		"Lighting": true,
		"Decals": true,
		"Collision": true,
		"Niagara": true,
		"Beams": true,
		"World labels": true,
		"Emissive plates": true,
		"Doors": true,
		"Loot": true,
		"Devices": true,
	}


func _consistency_checks(res: Dictionary, stats: Dictionary) -> Dictionary:
	var checks: Dictionary = {}
	var lights_expected: int = int(res.get("light_count", -1))
	var occl_expected: int = int(res.get("occluder_count", -1))
	var decal_expected: int = int(res.get("decal_count", -1))
	var bodies_expected: int = int(res.get("collision_bodies", -1))
	var shapes_expected: int = int(res.get("collision_shapes", -1))
	var niagara_systems: int = int(res.get("niagara_systems", -1))
	var mesh_instances: int = int(res.get("mesh_instances", -1))
	checks["lights"] = _check_exact("loader light_count (excl. GI fills)", lights_expected, int(stats["loader_lights"]))
	checks["occluders"] = _check_exact("loader occluder_count", occl_expected, int(stats["occluders"]))
	checks["decals"] = _check_exact("loader decal_count", decal_expected, int(stats["decals"]))
	checks["niagara_systems"] = _check_exact("loader niagara_systems", niagara_systems, int(stats["niagara_nodes"]))
	# StaticBody3D count can exceed the loader counter for authored extras the
	# loader adds outside _add_collider (Guildhall safe-room slab). Never less.
	checks["collision_bodies"] = _check_at_least("loader collision_bodies", bodies_expected, int(stats["collision_bodies"]))
	checks["collision_shapes"] = _check_at_least("loader collision_shapes", shapes_expected, int(stats["collision_shapes"]))
	# mesh_instances counts fog instances and procedural extras that carry no
	# ue_mesh, while tagged draws include loader-added doors/loot and can exceed
	# it. Neither direction is a contract, so this is informational only.
	checks["mesh_instances"] = _check_info("loader mesh_instances vs tagged ue_mesh draws", mesh_instances, int(stats["draw_instances"]))
	return checks


func _check_exact(label: String, expected: int, actual: int) -> Dictionary:
	return {"label": label, "expected": expected, "actual": actual, "ok": expected == actual}


func _check_at_least(label: String, expected: int, actual: int) -> Dictionary:
	return {"label": label, "expected": expected, "actual": actual, "ok": expected >= 0 and actual >= expected, "exact": expected == actual}


## Counts from mixed sources (fog extras vs tagged geometry) that must be
## recorded but cannot fail closed in either direction.
func _check_info(label: String, expected: int, actual: int) -> Dictionary:
	return {"label": label, "expected": expected, "actual": actual, "ok": true, "exact": expected == actual, "informational": true}


func _pick_loader_counts(res: Dictionary) -> Dictionary:
	var keys: Array[String] = [
		"chunk_count", "mesh_instances", "light_count", "rect_light_count",
		"occluder_count", "collision_bodies", "collision_shapes",
		"building_shapes", "decal_count", "decal_skipped",
		"niagara_placements", "niagara_spawned", "niagara_systems",
		"fog_volumes_built", "landscape_count", "missing_mesh_count",
		"corrupt_mesh_count", "fallback_material_count",
	]
	var out: Dictionary = {}
	for k: String in keys:
		if res.has(k):
			out[k] = res[k]
	# Landscapes are not a loader result key; count them from the JSON-backed
	# tagged nodes instead (see node_counts.kinds.landscape).
	return out


func _empty_totals() -> Dictionary:
	return {
		"chunks": 0, "mesh_instances": 0, "lights": 0, "occluders": 0,
		"collision_bodies": 0, "collision_shapes": 0, "decals": 0,
		"niagara_nodes": 0, "niagara_instances": 0, "nodes": 0, "surfaces": 0,
		"instances": 0, "landscapes": 0,
	}


func _accumulate_totals(totals: Dictionary, stats: Dictionary, res: Dictionary) -> void:
	totals["chunks"] = int(totals["chunks"]) + int(res.get("chunk_count", 0))
	totals["mesh_instances"] = int(totals["mesh_instances"]) + int(res.get("mesh_instances", 0))
	totals["lights"] = int(totals["lights"]) + int(stats["lights"])
	totals["occluders"] = int(totals["occluders"]) + int(stats["occluders"])
	totals["collision_bodies"] = int(totals["collision_bodies"]) + int(stats["collision_bodies"])
	totals["collision_shapes"] = int(totals["collision_shapes"]) + int(stats["collision_shapes"])
	totals["decals"] = int(totals["decals"]) + int(stats["decals"])
	totals["niagara_nodes"] = int(totals["niagara_nodes"]) + int(stats["niagara_nodes"])
	totals["niagara_instances"] = int(totals["niagara_instances"]) + int(stats["niagara_instances"])
	totals["nodes"] = int(totals["nodes"]) + int(stats["nodes"])
	totals["surfaces"] = int(totals["surfaces"]) + int(stats["surfaces"])
	totals["instances"] = int(totals["instances"]) + int(stats["instances"])
	totals["landscapes"] = int(totals["landscapes"]) + int((stats["kinds"] as Dictionary).get("landscape", 0))


func _bookmarks_for_manifest(map_id: String) -> Array:
	var out: Array = []
	for b: Dictionary in MapData.bookmarks_for(map_id):
		out.append({
			"name": b.get("name", ""),
			"pos": _vec_to_array(b.get("pos", Vector3.ZERO)),
			"target": _vec_to_array(b.get("target", Vector3.ZERO)),
			"source": b.get("source", ""),
		})
	return out


func _aabb_to_dict(stats: Dictionary) -> Dictionary:
	if not bool(stats["has_aabb"]):
		return {}
	var box: AABB = stats["aabb"] as AABB
	return {
		"position": _vec_to_array(box.position),
		"size": _vec_to_array(box.size),
	}


func _vec_to_array(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## Loader draw items are unnamed, so Godot names them @MeshInstance3D@123 and
## the editor tree is unreadable. Rename from the authored mesh stem / node
## class. Names are cosmetic; nothing consumes them.
func _name_review_nodes(root: Node) -> void:
	var counts: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.push_back(c)
		var base: String = ""
		if n.has_meta("ue_mesh"):
			base = str(n.get_meta("ue_mesh")).get_file().split(".")[0]
		if base == "":
			var kind: String = str(n.get_meta("review_kind", ""))
			if kind == "landscape":
				base = "Landscape"
			elif kind == "fog":
				base = "FogVolume"
			elif kind == "collision":
				base = "Collision" if n is StaticBody3D else ""
			elif kind == "light":
				if str(n.name).begins_with("SkylightLeakingFill_"):
					base = "SkylightLeakingFill"
				else:
					base = str(n.get_class()).replace("3D", "")
		if base == "":
			continue
		var count: int = int(counts.get(base, 0)) + 1
		counts[base] = count
		n.name = "%s_%d" % [base, count]


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)


func _file_size(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var size: int = f.get_length()
	f.close()
	return size


func _globalize(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _git_sha() -> String:
	var out: Array = []
	var code: int = OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"], out, true)
	if code != 0 or out.is_empty():
		return "unknown"
	return str(out[0]).strip_edges()


func _append_log(line: String) -> void:
	_log.append(line)
	print("REVIEW_BAKE ", line)
