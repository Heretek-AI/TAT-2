extends SceneTree
## W1p headless structural-perf test.
##
## Covers the prototype levers without any GPU work:
##   - source_sublevel provenance on real Guildhall draw items;
##   - TAT2_PERIPH_RANGE applies only to PeripheryA chunks;
##   - TAT2_SHADOW_HEROES / TAT2_LIGHT_BUDGET change the selection counts;
##   - TAT2_MERGE_CELLS=plain folds two same-material plain mesh instances in
##     one 32 m cell into one node/one surface, and a two-material pair into one
##     node with two surfaces in authored order, while collision stays intact.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_perf_structural.gd

const PERIPH_PATH := "res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json"
const MERGE_BOX := "/Game/Test/Perf/SM_MergeProbeWallBox"
const MERGE_MULTI := "/Game/Test/Perf/SM_MergeProbeWallMulti"
const RANGE_WALL := "/Game/Test/Perf/SM_PerfRangeWall"

var fails: int = 0


func _initialize() -> void:
	await process_frame
	await _test_guildhall_source_metadata()
	await _test_periph_range()
	await _test_light_env_overrides()
	await _test_merge_single_material()
	await _test_merge_multi_material()
	await _test_merge_transparent_rejected()
	_clear_env()
	print("PERF_STRUCTURAL_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		printerr("FAIL: ", msg)
		fails += 1


func _clear_env() -> void:
	OS.set_environment("TAT2_PERIPH_RANGE", "")
	OS.set_environment("TAT2_SHADOW_HEROES", "")
	OS.set_environment("TAT2_LIGHT_BUDGET", "")
	OS.set_environment("TAT2_MERGE_CELLS", "")


func _new_loader() -> Node:
	var ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ll)
	return ll


func _make_host(name: String) -> Node3D:
	var host := Node3D.new()
	host.name = name
	root.add_child(host)
	return host


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func _box_mesh(size: Vector3, mat: Material) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	box.surface_set_material(0, mat)
	return box


func _multi_mesh(mat_a: Material, mat_b: Material) -> ArrayMesh:
	var source := BoxMesh.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(0))
	mesh.surface_set_material(0, mat_a)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(0))
	mesh.surface_set_material(1, mat_b)
	return mesh


func _mesh_entry(mesh: Mesh, shape_size: Vector3) -> Dictionary:
	var shape := BoxShape3D.new()
	shape.size = shape_size
	return {"mesh": mesh, "shape": shape, "shape_offset": Vector3.ZERO}


func _plain_item(mp: String, pos: Vector3, source: String, collide: bool = true) -> Dictionary:
	return {
		"mp": mp,
		"override_materials": [],
		"override_key": "",
		"trs": [Transform3D(Basis.IDENTITY, pos)],
		"cpds": [] as Array[Color],
		"hidden_in_game": false,
		"collide": collide,
		"cell": Vector2i(floori(pos.x / 32.0), floori(pos.z / 32.0)),
		"source_sublevel": source,
		"source_sublevels": [source],
		"source_counts": {source: 1},
	}


func _count_type(parent: Node, type_name: String) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child.is_class(type_name):
			count += 1
	return count


func _merged_node(parent: Node) -> MeshInstance3D:
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _test_guildhall_source_metadata() -> void:
	_clear_env()
	var ll := _new_loader()
	var host := _make_host("PerfSourceHost")
	var acc: Dictionary = ll.call("_new_accumulator") as Dictionary
	ll.call("_parse_sublevel_file", PERIPH_PATH, acc, host)
	var items: Array = ll.call("_collect_draw_items", acc) as Array
	var missing: int = 0
	var wrong: int = 0
	var tagged: int = 0
	for item_var: Variant in items:
		if not (item_var is Dictionary):
			continue
		var item: Dictionary = item_var as Dictionary
		if not item.has("source_sublevel"):
			missing += 1
		elif str(item.get("source_sublevel", "")) != "Guildhall_PeripheryA":
			wrong += 1
		else:
			tagged += 1
	_check(not items.is_empty() and missing == 0 and wrong == 0 and tagged == items.size(),
		"Guildhall PeripheryA draw items carry source_sublevel (%d items, missing=%d wrong=%d)" % [items.size(), missing, wrong])
	host.queue_free()
	ll.queue_free()
	await process_frame


func _test_periph_range() -> void:
	_clear_env()
	OS.set_environment("TAT2_PERIPH_RANGE", "100")
	var ll := _new_loader()
	var host := _make_host("PerfRangeHost")
	var mat := _material(Color(0.5, 0.5, 0.5))
	var cache: Dictionary = {
		RANGE_WALL: _mesh_entry(_box_mesh(Vector3(5, 5, 5), mat), Vector3(5, 5, 5)),
	}
	ll.set("_mesh_res_cache", cache)
	var ctx: Dictionary = ll.call("_new_build_ctx", host, null, false) as Dictionary
	var periph_item: Dictionary = _plain_item(RANGE_WALL, Vector3.ZERO, "Guildhall_PeripheryA", false)
	var interior_item: Dictionary = _plain_item(RANGE_WALL, Vector3(64, 0, 0), "Building_Guildhall_POI", false)
	var sky_item: Dictionary = _plain_item(RANGE_WALL, Vector3(128, 0, 0), "Guildhall_SkyboxGeo", false)
	sky_item["far"] = true
	var mixed_item: Dictionary = _plain_item(RANGE_WALL, Vector3(192, 0, 0), "mixed", false)
	mixed_item["source_sublevels"] = ["Guildhall_PeripheryA", "Building_Guildhall_POI"]
	for item: Dictionary in [periph_item, interior_item, sky_item, mixed_item]:
		ll.call("_build_one_draw_item", item, host, ctx)
	var mesh_nodes: Array = []
	for child: Node in host.get_children():
		if child is MeshInstance3D:
			mesh_nodes.append(child)
	var periph_node: GeometryInstance3D = mesh_nodes[0] as GeometryInstance3D
	var interior_node: GeometryInstance3D = mesh_nodes[1] as GeometryInstance3D
	var sky_node: GeometryInstance3D = mesh_nodes[2] as GeometryInstance3D
	var mixed_node: GeometryInstance3D = mesh_nodes[3] as GeometryInstance3D
	var expected: float = 100.0 + 16.0
	_check(periph_node != null and is_equal_approx(periph_node.visibility_range_end, expected) \
			and periph_node.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
		"PERIPH_RANGE=100 sets PeripheryA range %.1f with fade disabled" % expected)
	_check(interior_node != null and interior_node.visibility_range_end == 0.0 \
			and sky_node != null and sky_node.visibility_range_end == 0.0 \
			and mixed_node != null and mixed_node.visibility_range_end == 0.0,
		"range stays off for interior, SkyboxGeo and mixed batches")
	_check(int(ctx.get("periph_range_applied", 0)) == 1 and int(ctx.get("periph_range_skipped_mixed", 0)) == 1,
		"range counters applied=1 skipped_mixed=1")
	host.queue_free()
	ll.queue_free()
	await process_frame


func _test_light_env_overrides() -> void:
	_clear_env()
	OS.set_environment("TAT2_SHADOW_HEROES", "2")
	OS.set_environment("TAT2_LIGHT_BUDGET", "64")
	var mp: GDScript = load("res://src/core/mobile_profile.gd") as GDScript
	var shadows: int = int(mp.call("hero_shadows"))
	var budget: int = int(mp.call("light_budget", 160))
	var ll := _new_loader()
	var ordered: Array = []
	for i: int in range(100):
		ordered.append({"intensity": 15.0 + float(i), "pos": [float(i), 0.0, 0.0], "type": "Point"})
	var selection: Array = ll.call("_select_lights", ordered, budget, "test") as Array
	var shadow_count: int = 0
	for sel_var: Variant in selection:
		if bool((sel_var as Dictionary).get("shadow", false)):
			shadow_count += 1
	_check(shadows == 2 and budget == 64 and selection.size() == 64 and shadow_count == 2,
		"TAT2_SHADOW_HEROES=2 / TAT2_LIGHT_BUDGET=64 select 64 lights with 2 hero shadows")
	var host := _make_host("PerfLightBudgetHost")
	var ctx: Dictionary = ll.call("_new_build_ctx", host, null, false) as Dictionary
	ctx["map_hint"] = "guildhall"
	ctx["light_budget"] = budget
	ll.call("_add_lights", ordered, host, null, budget, ctx, [])
	_check(int(ctx.get("light_count", 0)) == 64 and int(ctx.get("hero_shadows", 0)) == 2,
		"loader applies the logged budget (light_count=%d hero_shadows=%d)" % [int(ctx.get("light_count", 0)), int(ctx.get("hero_shadows", 0))])
	host.queue_free()
	OS.set_environment("TAT2_SHADOW_HEROES", "")
	OS.set_environment("TAT2_LIGHT_BUDGET", "")
	_check(int(mp.call("hero_shadows")) == 6 and int(mp.call("light_budget", 160)) == 160,
		"defaults restore hero_shadows=6 and light_budget=160")
	ll.queue_free()
	await process_frame


func _test_merge_single_material() -> void:
	_clear_env()
	OS.set_environment("TAT2_MERGE_CELLS", "plain")
	var ll := _new_loader()
	var host := _make_host("PerfMergeSingleHost")
	var mat := _material(Color(0.2, 0.6, 0.3))
	var cache: Dictionary = {MERGE_BOX: _mesh_entry(_box_mesh(Vector3.ONE, mat), Vector3.ONE)}
	ll.set("_mesh_res_cache", cache)
	var ctx: Dictionary = ll.call("_new_build_ctx", host, null, true) as Dictionary
	var item_a: Dictionary = _plain_item(MERGE_BOX, Vector3.ZERO, "Guildhall_PeripheryA")
	var item_b: Dictionary = _plain_item(MERGE_BOX, Vector3(2, 0, 0), "Guildhall_PeripheryA")
	var items: Array = [item_a, item_b]
	var total: int = int(ll.call("_build_draw_items", items, host, ctx))
	var merged: MeshInstance3D = _merged_node(host)
	var mesh_surfaces: int = merged.mesh.get_surface_count() if merged != null and merged.mesh != null else -1
	var verts: int = -1
	if merged != null and merged.mesh != null and mesh_surfaces == 1:
		verts = (merged.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var aabb_ok: bool = merged != null and merged.custom_aabb.position.x < -0.4 and merged.custom_aabb.end.x > 2.4
	_check(total == 2 and _count_type(host, "MeshInstance3D") == 1 and mesh_surfaces == 1 and verts == 48 and aabb_ok,
		"plain merge: one node, one surface, 48 verts, tight AABB over both boxes (total=%d surfaces=%d verts=%d)" % [total, mesh_surfaces, verts])
	_check(int(ctx.get("collision_shapes", 0)) == 2 and int(ctx.get("collision_bodies", 0)) == 1,
		"plain merge keeps collision (bodies=%d shapes=%d)" % [int(ctx.get("collision_bodies", 0)), int(ctx.get("collision_shapes", 0))])
	_check(int(ctx.get("merge_candidates", 0)) == 2 and int(ctx.get("merge_cells", 0)) == 1 \
			and int(ctx.get("merge_surfaces_before", 0)) == 2 and int(ctx.get("merge_surfaces_after", 0)) == 1 \
			and bool(item_a.get("_merge_skip_visual", false)),
		"plain merge accounting candidates=2 cells=1 surfaces 2->1")
	host.queue_free()
	ll.queue_free()
	await process_frame


func _test_merge_multi_material() -> void:
	_clear_env()
	OS.set_environment("TAT2_MERGE_CELLS", "plain")
	var ll := _new_loader()
	var host := _make_host("PerfMergeMultiHost")
	var mat_a := _material(Color(0.8, 0.2, 0.2))
	var mat_b := _material(Color(0.2, 0.2, 0.8))
	var mesh := _multi_mesh(mat_a, mat_b)
	var cache: Dictionary = {MERGE_MULTI: _mesh_entry(mesh, Vector3.ONE)}
	ll.set("_mesh_res_cache", cache)
	var ctx: Dictionary = ll.call("_new_build_ctx", host, null, true) as Dictionary
	var items: Array = [
		_plain_item(MERGE_MULTI, Vector3.ZERO, "Guildhall_Geometry"),
		_plain_item(MERGE_MULTI, Vector3(2, 0, 0), "Guildhall_Geometry"),
	]
	var total: int = int(ll.call("_build_draw_items", items, host, ctx))
	var merged: MeshInstance3D = _merged_node(host)
	var surfaces: int = merged.mesh.get_surface_count() if merged != null and merged.mesh != null else -1
	var order_ok: bool = surfaces == 2 and merged.mesh.surface_get_material(0) == mat_a and merged.mesh.surface_get_material(1) == mat_b
	_check(total == 2 and _count_type(host, "MeshInstance3D") == 1 and order_ok,
		"multi-material merge: one node, two surfaces, authored material order preserved")
	_check(int(ctx.get("merge_surfaces_before", 0)) == 4 and int(ctx.get("merge_surfaces_after", 0)) == 2 \
			and int(ctx.get("collision_shapes", 0)) == 2,
		"multi-material accounting surfaces 4->2, collision shapes=2")
	host.queue_free()
	ll.queue_free()
	await process_frame


func _test_merge_transparent_rejected() -> void:
	_clear_env()
	OS.set_environment("TAT2_MERGE_CELLS", "plain")
	var ll := _new_loader()
	var host := _make_host("PerfMergeTransparentHost")
	var mat := _material(Color(0.5, 0.5, 0.5, 0.5))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cache: Dictionary = {MERGE_BOX: _mesh_entry(_box_mesh(Vector3.ONE, mat), Vector3.ONE)}
	ll.set("_mesh_res_cache", cache)
	var ctx: Dictionary = ll.call("_new_build_ctx", host, null, false) as Dictionary
	var items: Array = [
		_plain_item(MERGE_BOX, Vector3.ZERO, "Guildhall_PeripheryA", false),
		_plain_item(MERGE_BOX, Vector3(2, 0, 0), "Guildhall_PeripheryA", false),
	]
	ll.call("_build_draw_items", items, host, ctx)
	var skipped: Dictionary = ctx.get("merge_skipped", {}) as Dictionary
	_check(int(ctx.get("merge_candidates", 0)) == 0 and int(skipped.get("transparent", 0)) == 2 \
			and _count_type(host, "MeshInstance3D") == 2,
		"transparent surfaces fail closed (candidates=0 reason=transparent, both originals kept)")
	host.queue_free()
	ll.queue_free()
	await process_frame
