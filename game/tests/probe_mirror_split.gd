extends SceneTree
## P4.2 mirror-split data test (headless, no GPU).
##
## Proves, against the real generated payload and a real level build:
##   1. the bake math (winding, normals, tangents, materials, mirrored AABB);
##   2. the cull-front fast path never mutates a shared material;
##   3. every authored negative-determinant Guildhall mesh record reaches the
##      exact partition helper the draw build uses;
##   4. in a real build every negative instance is in a tagged `neg` batch or
##      a tagged mirrored standalone node, and no untagged node hides one;
##   5. `mirrored_multimesh + mirrored_single == mirrored_bases` per load;
##   6. every split item apportions `source_counts` exactly once (P4.2
##      PERF_CENSUS fix), and the full 17-sublevel load reproduces the
##      pre-split `PERF_CENSUS.source_sublevels` total of 64,660.
##
## Run:
##   tools/godot --headless --path game --script res://tests/probe_mirror_split.gd
##   tools/godot --headless --path game --script res://tests/probe_mirror_split.gd -- --full
##
## `--full` loads the complete Guildhall contract-4 sublevel set (15 base +
## `Guildhall_Contract_04` + `Guildhall_Contract_Teleporters`), matching the
## `make test` mission load and its 64,660 source-count baseline. The default
## is the fast Guildhall_Geometry gate.

const LEVELS_ROOT := "res://data/generated/levels/"
const FLIP_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
const FULL_EXTRA: Array[String] = [
	"Guildhall/Guildhall_Contract_04",
	"Guildhall/Guildhall_Contract_Teleporters",
]
const GUILDHALL_SUBLEVELS: Array[String] = [
	"Buildings/Guildhall/Building_Guildhall_POI",
	"Buildings/Guildhall/Building_Guildhall_POI_3rdFloor",
	"Buildings/Guildhall/Guildhall_Vault_CeremonialChambers",
	"Guildhall/Guildhall_Gameplay",
	"Guildhall/Guildhall_P",
	"Guildhall/Guildhall_Geometry",
	"Guildhall/Guildhall_Landscape",
	"Guildhall/Guildhall_LightingNoGameplay",
	"Guildhall/Guildhall_LocalVolumetric",
	"Guildhall/Guildhall_PeripheryA",
	"Guildhall/Guildhall_Loot",
	"Guildhall/Guildhall_Contracts",
	"Guildhall/Guildhall_SetSpawners",
	"Guildhall/Guildhall_MissionClues",
	"Guildhall/Guildhall_SkyboxGeo",
]

var _fails: int = 0
var _checks: int = 0
var _ll: Node = null


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String, detail: String) -> void:
	_checks += 1
	if ok:
		print("PASS: ", name, " ", detail)
	else:
		_fails += 1
		printerr("FAIL: ", name, " ", detail)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt: String = FileAccess.get_file_as_string(path)
	if txt == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	return parsed as Dictionary if parsed is Dictionary else {}


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var full: bool = args.has("--full")
	var ll_script: GDScript = load("res://src/core/level_loader.gd") as GDScript
	_ll = ll_script.new() as Node
	root.add_child(_ll)

	_test_bake()
	_test_fast_path()
	_test_source_split()
	var authored_neg: int = _test_static_partition()
	_test_real_load(full, authored_neg)

	print("MIRROR_DATA_SUMMARY: fails=%d checks=%d mode=%s" % [
		_fails, _checks, "full" if full else "geometry"])
	_ll.queue_free()
	quit(1 if _fails > 0 else 0)


## A single-triangle source with explicit vertex data, used by the bake and
## fast-path unit tests (no GLB import needed).
func _tri_mesh(mat: Material) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1.0, -1.0, 0.0), Vector3(1.0, -1.0, 0.0), Vector3(0.0, 1.0, 0.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0)])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([
		1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(0.5, 0.0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, mat)
	return m


func _test_bake() -> void:
	var info: Dictionary = _ll.call("_get_mesh_and_shape",
		"/Game/Art/Environment/OldManor/SM_OldManor_Door_1x3") as Dictionary
	var src: Mesh = info.get("mesh") as Mesh
	if src == null:
		_check(false, "bake source mesh present", "SM_OldManor_Door_1x3 not loadable")
		return
	_ll.call("_reset_mirror_counters")
	var variant: Dictionary = _ll.call("_get_mirror_variant", src, "unit", false) as Dictionary
	var baked: Mesh = variant.get("mesh") as Mesh
	_check(str(variant.get("mode", "")) == "baked" and baked != null and baked != src,
		"bake produces a distinct ArrayMesh",
		"mode=%s baked=%s" % [str(variant.get("mode", "")), str(baked != null)])
	if baked == null:
		return
	_check(baked.get_surface_count() == src.get_surface_count(),
		"bake keeps the surface count",
		"src=%d baked=%d" % [src.get_surface_count(), baked.get_surface_count()])
	var mats_ok: bool = true
	for s: int in range(mini(src.get_surface_count(), baked.get_surface_count())):
		if baked.surface_get_material(s) != src.surface_get_material(s):
			mats_ok = false
	_check(mats_ok, "bake reuses the authored surface materials (same resources)",
		"surfaces=%d" % baked.get_surface_count())
	# S = diag(-1,1,1): xmin' = -xmax, xmax' = -xmin.
	var sa: AABB = src.get_aabb()
	var ba: AABB = baked.get_aabb()
	var expect_pos := Vector3(-sa.position.x - sa.size.x, sa.position.y, sa.position.z)
	_check(ba.position.distance_to(expect_pos) < 0.0001 and ba.size.distance_to(sa.size) < 0.0001,
		"baked AABB is the local-X mirror",
		"src=%s baked=%s want_pos=%s" % [str(sa), str(ba), str(expect_pos)])
	_check(bool(baked.get_meta("mirror_baked", false)) and int(baked.get_meta("mirror_bytes", 0)) > 0,
		"baked mesh carries the provenance/byte metadata",
		"bytes=%d" % int(baked.get_meta("mirror_bytes", 0)))
	# Winding: every source triangle (a,b,c) becomes (a,c,b).
	var winding_ok: bool = true
	var normals_ok: bool = true
	var tangents_ok: bool = true
	for s2: int in range(mini(src.get_surface_count(), baked.get_surface_count())):
		var sa2: Array = src.surface_get_arrays(s2)
		var ba2: Array = baked.surface_get_arrays(s2)
		var si: PackedInt32Array = sa2[Mesh.ARRAY_INDEX] as PackedInt32Array
		var bi: PackedInt32Array = ba2[Mesh.ARRAY_INDEX] as PackedInt32Array
		if si.size() != bi.size():
			winding_ok = false
		else:
			var t: int = 0
			while t + 2 < si.size():
				if si[t] != bi[t] or si[t + 1] != bi[t + 2] or si[t + 2] != bi[t + 1]:
					winding_ok = false
					break
				t += 3
		var sn: PackedVector3Array = sa2[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var bn: PackedVector3Array = ba2[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var nlimit: int = mini(sn.size(), bn.size())
		for i: int in range(nlimit):
			if absf(bn[i].x + sn[i].x) > 0.02 or absf(bn[i].y - sn[i].y) > 0.02 or absf(bn[i].z - sn[i].z) > 0.02:
				normals_ok = false
				break
		var st: PackedFloat32Array = sa2[Mesh.ARRAY_TANGENT] as PackedFloat32Array
		var bt: PackedFloat32Array = ba2[Mesh.ARRAY_TANGENT] as PackedFloat32Array
		var tlimit: int = mini(st.size(), bt.size())
		var ti: int = 0
		while ti + 3 < tlimit:
			if absf(bt[ti] + st[ti]) > 0.02 or absf(bt[ti + 1] - st[ti + 1]) > 0.02 \
					or absf(bt[ti + 2] - st[ti + 2]) > 0.02 or absf(bt[ti + 3] + st[ti + 3]) > 0.02:
				tangents_ok = false
				break
			ti += 4
	_check(winding_ok, "baked triangle winding is reversed", "surfaces=%d" % src.get_surface_count())
	_check(normals_ok, "baked normals negate x", "surfaces=%d" % src.get_surface_count())
	_check(tangents_ok, "baked tangents negate x and w", "surfaces=%d" % src.get_surface_count())
	# The shared source must not be touched.
	var src_aabb_after: AABB = src.get_aabb()
	_check(src_aabb_after.position.distance_to(sa.position) < 0.000001
		and src_aabb_after.size.distance_to(sa.size) < 0.000001,
		"bake does not mutate the source mesh", "src=%s" % str(src_aabb_after))
	# The cache must return the same variant instance.
	var again: Dictionary = _ll.call("_get_mirror_variant", src, "unit", false) as Dictionary
	_check((again.get("mesh") as Mesh) == baked, "bake variant is cached by mesh+override",
		"same=%s" % str((again.get("mesh") as Mesh) == baked))


func _test_fast_path() -> void:
	var prev_fast: String = OS.get_environment("TAT2_MIRROR_FAST")
	OS.set_environment("TAT2_MIRROR_FAST", "on")
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var tri: ArrayMesh = _tri_mesh(mat)
	_ll.call("_reset_mirror_counters")
	var fast: Dictionary = _ll.call("_get_mirror_variant", tri, "fast", true) as Dictionary
	var clone: BaseMaterial3D = fast.get("material") as BaseMaterial3D
	_check(str(fast.get("mode", "")) == "cull_front" and (fast.get("mesh") as Mesh) == tri,
		"single-surface BaseMaterial3D uses the CULL_FRONT fast path",
		"mode=%s" % str(fast.get("mode", "")))
	_check(clone != null and clone.cull_mode == BaseMaterial3D.CULL_FRONT,
		"fast path clones the material as CULL_FRONT",
		"clone=%s" % str(clone != null))
	_check(mat.cull_mode == BaseMaterial3D.CULL_BACK,
		"fast path never mutates the shared source material",
		"source_cull=%d" % mat.cull_mode)
	# A two-sided source needs no flip and keeps its material.
	var two := StandardMaterial3D.new()
	two.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tri2: ArrayMesh = _tri_mesh(two)
	var two_variant: Dictionary = _ll.call("_get_mirror_variant", tri2, "two", true) as Dictionary
	_check(str(two_variant.get("mode", "")) == "cull_disabled",
		"two-sided single-surface source uses the cull-disabled path",
		"mode=%s" % str(two_variant.get("mode", "")))
	# Fast path can be disabled for the probe's A/B.
	OS.set_environment("TAT2_MIRROR_FAST", "off")
	var slow: Dictionary = _ll.call("_get_mirror_variant", tri, "slow", true) as Dictionary
	if prev_fast == "":
		OS.unset_environment("TAT2_MIRROR_FAST")
	else:
		OS.set_environment("TAT2_MIRROR_FAST", prev_fast)
	_check(str(slow.get("mode", "")) == "baked",
		"TAT2_MIRROR_FAST=off falls back to the baked mesh",
		"mode=%s" % str(slow.get("mode", "")))


static func _dict_sum(d: Dictionary) -> int:
	var n: int = 0
	for k: Variant in d.keys():
		n += int(d[k])
	return n


static func _dicts_add_equal(a: Dictionary, b: Dictionary, whole: Dictionary) -> bool:
	var keys: Dictionary = {}
	for k: Variant in a.keys():
		keys[str(k)] = true
	for k: Variant in b.keys():
		keys[str(k)] = true
	for k: Variant in whole.keys():
		keys[str(k)] = true
	for k: Variant in keys.keys():
		if int(a.get(k, 0)) + int(b.get(k, 0)) != int(whole.get(k, 0)):
			return false
	return true


## The P4.2 accounting fix: split_source_counts must apportion the item's
## source map exactly once (pos + neg == item), with no rounding loss and a
## deterministic tie-break. These are the regression cases for PERF_CENSUS.
func _test_source_split() -> void:
	var cases: Array = [
		{"counts": {"A": 10, "B": 5}, "total": 15, "neg": 0},
		{"counts": {"A": 10, "B": 5}, "total": 15, "neg": 15},
		{"counts": {"A": 10, "B": 5}, "total": 15, "neg": 1},
		{"counts": {"A": 10, "B": 5}, "total": 15, "neg": 7},
		{"counts": {"A": 10, "B": 5}, "total": 15, "neg": 14},
		{"counts": {"Guildhall_PeripheryA": 52, "Building_Guildhall_POI": 12}, "total": 64, "neg": 13},
		{"counts": {"A": 1, "B": 1, "C": 1}, "total": 3, "neg": 1},
		{"counts": {"A": 999, "B": 1, "C": 1}, "total": 1001, "neg": 500},
	]
	var all_ok: bool = true
	var deterministic: bool = true
	var sums_ok: bool = true
	for c_var: Variant in cases:
		var c: Dictionary = c_var as Dictionary
		var counts: Dictionary = c["counts"] as Dictionary
		var total: int = int(c["total"])
		var neg_n: int = int(c["neg"])
		var a: Dictionary = _ll.call("split_source_counts", counts, total, neg_n) as Dictionary
		var b: Dictionary = _ll.call("split_source_counts", counts, total, neg_n) as Dictionary
		var pos: Dictionary = a.get("pos", {}) as Dictionary
		var neg: Dictionary = a.get("neg", {}) as Dictionary
		if not _dicts_add_equal(pos, neg, counts):
			all_ok = false
		if _dict_sum(pos) + _dict_sum(neg) != _dict_sum(counts):
			sums_ok = false
		if str(a) != str(b):
			deterministic = false
		if pos != b.get("pos", {}) or neg != b.get("neg", {}):
			deterministic = false
		if neg_n == 0 and not pos.is_empty() and _dict_sum(neg) != 0:
			all_ok = false
		if neg_n == total and _dict_sum(pos) != 0:
			all_ok = false
	_check(all_ok, "split_source_counts apportions pos+neg == item for every key",
		"cases=%d" % cases.size())
	_check(sums_ok, "split_source_counts preserves the total with no rounding loss",
		"cases=%d" % cases.size())
	_check(deterministic, "split_source_counts is deterministic across calls",
		"cases=%d" % cases.size())
	# Largest-remainder tie-break: sorted key wins the single remainder.
	var tie: Dictionary = _ll.call("split_source_counts",
		{"A": 1, "B": 1, "C": 1}, 3, 1) as Dictionary
	_check(str(tie.get("neg", {})) == str({"A": 1}),
		"split_source_counts tie-break is the sorted key",
		"neg=%s" % str(tie.get("neg", {})))


## Returns the authored negative-record count for the Guildhall set.
func _test_static_partition() -> int:
	var authored_neg: int = 0
	var groups: Dictionary = {}
	var records: int = 0
	for sub: String in GUILDHALL_SUBLEVELS:
		var d: Dictionary = _read_json(LEVELS_ROOT + sub + ".tatlevel.json")
		for m_var: Variant in (d.get("meshes", []) as Array):
			if not (m_var is Dictionary):
				continue
			var rec: Dictionary = m_var as Dictionary
			records += 1
			var mp: String = str(rec.get("mesh", ""))
			var tr: Transform3D = _ll.call("_dict_to_transform", rec) as Transform3D
			var neg: bool = tr.basis.determinant() < 0.0
			if neg:
				authored_neg += 1
			var key: String = mp + "||" + str(rec.get("pos", []))
			var arr: Array = groups.get(key, [] as Array) as Array
			arr.append(tr)
			groups[key] = arr
	var group_neg: int = 0
	var partition_ok: bool = true
	var normalize_ok: bool = true
	for key_v: Variant in groups.keys():
		var trs: Array = groups[key_v] as Array
		var split: Dictionary = _ll.call("partition_mirror_indices", trs) as Dictionary
		var pos: Array = split.get("pos", [] as Array) as Array
		var neg_i: Array = split.get("neg", [] as Array) as Array
		if pos.size() + neg_i.size() != trs.size():
			partition_ok = false
		var seen: Dictionary = {}
		for pi_v: Variant in pos:
			var pi: int = int(pi_v)
			if seen.has(pi):
				partition_ok = false
			seen[pi] = true
			if (trs[pi] as Transform3D).basis.determinant() < 0.0:
				partition_ok = false
		for ni_v: Variant in neg_i:
			var ni: int = int(ni_v)
			if seen.has(ni):
				partition_ok = false
			seen[ni] = true
			var trn: Transform3D = trs[ni]
			if trn.basis.determinant() >= 0.0:
				partition_ok = false
			# The baked path right-multiplies by S; det must become positive.
			if (trn.basis * FLIP_X).determinant() <= 0.0:
				normalize_ok = false
		group_neg += neg_i.size()
	_check(records > 0 and authored_neg > 0,
		"Guildhall payload carries authored mirrored records",
		"records=%d authored_neg=%d" % [records, authored_neg])
	_check(partition_ok, "partition covers every record exactly once",
		"groups=%d" % groups.size())
	_check(group_neg == authored_neg,
		"every authored negative record lands in a neg batch",
		"authored=%d partition_neg=%d" % [authored_neg, group_neg])
	_check(normalize_ok, "B*S normalization makes every neg basis positive",
		"neg=%d" % group_neg)
	print("MIRROR_STATIC_GUILDHALL records=%d authored_neg=%d groups=%d groups_with_neg=%d" % [
		records, authored_neg, groups.size(), _count_neg_groups(groups)])
	return authored_neg


func _count_neg_groups(groups: Dictionary) -> int:
	var n: int = 0
	for key_v: Variant in groups.keys():
		var trs: Array = groups[key_v] as Array
		for tr_v: Variant in trs:
			if (tr_v as Transform3D).basis.determinant() < 0.0:
				n += 1
				break
	return n


func _effective_cull(gi: GeometryInstance3D, surface: int) -> int:
	var mat: Material = null
	var mi: MeshInstance3D = gi as MeshInstance3D
	if mi != null:
		mat = mi.material_override
		if mat == null:
			mat = mi.get_surface_override_material(surface)
		if mat == null and mi.mesh != null:
			mat = mi.mesh.surface_get_material(surface)
		return (mat as BaseMaterial3D).cull_mode if mat is BaseMaterial3D else -1
	var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
	if mmi != null:
		mat = mmi.material_override
		if mat == null and mmi.multimesh != null and mmi.multimesh.mesh != null:
			mat = mmi.multimesh.mesh.surface_get_material(surface)
		return (mat as BaseMaterial3D).cull_mode if mat is BaseMaterial3D else -1
	return -1


func _test_real_load(full: bool, authored_neg: int) -> void:
	var paths: Array[String] = []
	if full:
		for sub: String in GUILDHALL_SUBLEVELS:
			paths.append(LEVELS_ROOT + sub + ".tatlevel.json")
		for sub2: String in FULL_EXTRA:
			paths.append(LEVELS_ROOT + sub2 + ".tatlevel.json")
	else:
		paths.append(LEVELS_ROOT + "Guildhall/Guildhall_Geometry.tatlevel.json")
	var host := Node3D.new()
	root.add_child(host)
	var res: Dictionary = _ll.call("load_sublevels", paths, host, null, 8, false) as Dictionary
	var draw_bases: int = int(res.get("mirrored_bases", -1))
	var mm_n: int = int(res.get("mirrored_multimesh", -1))
	var single_n: int = int(res.get("mirrored_single", -1))
	var split_n: int = int(res.get("mirrored_batches_split", -1))
	_check(draw_bases == mm_n + single_n,
		"MIRROR_RECON identity on the real load",
		"bases=%d multimesh=%d single=%d" % [draw_bases, mm_n, single_n])
	_check(int(res.get("mirrored_unbaked", -1)) == 0,
		"no mirrored instance fell through unbaked",
		"unbaked=%d" % int(res.get("mirrored_unbaked", -1)))
	if full:
		_check(int(res.get("mirrored_transform_bases", -1)) >= draw_bases,
			"transform census covers the draw census (decals/GC excluded from draws)",
			"transform=%d draw=%d authored=%d" % [
				int(res.get("mirrored_transform_bases", -1)), draw_bases, authored_neg])
		# Same load as the `make test` Guildhall mission: baseline values from
		# docs/reports/logs/final/run_tests.log:245-247. P4.2's split must not
		# change the instance or source-count totals.
		_check(int(res.get("authored_meshes", -1)) == 64956,
			"full load authored count matches the mission baseline",
			"authored=%d" % int(res.get("authored_meshes", -1)))
		_check(int(res.get("mesh_instances", -1)) == 64685,
			"full load applied count matches the mission baseline",
			"applied=%d" % int(res.get("mesh_instances", -1)))
	var census: Dictionary = res.get("perf_census", {}) as Dictionary
	var src_totals: Dictionary = census.get("source_sublevels", {}) as Dictionary
	var src_sum: int = 0
	for src_v: Variant in src_totals.values():
		src_sum += int(src_v)
	if full:
		_check(int(census.get("mesh_instances", -1)) == 65132,
			"full PERF_CENSUS instance count matches the mission baseline",
			"instances=%d" % int(census.get("mesh_instances", -1)))
		_check(int(census.get("periph_instances", -1)) == 13446,
			"full PERF_CENSUS PeripheryA instance count matches the baseline",
			"periph_instances=%d" % int(census.get("periph_instances", -1)))
		_check(src_sum == 64660,
			"PERF_CENSUS.source_sublevels equals the pre-split baseline",
			"src_sum=%d want=64660" % src_sum)
	else:
		_check(src_sum > 0,
			"geometry PERF_CENSUS source counts are populated",
			"src_sum=%d instances=%d" % [src_sum, int(census.get("mesh_instances", 0))])
	var walk: Dictionary = _walk_mirror_nodes(host)
	_check(int(walk["tagged_mm"]) == mm_n and int(walk["tagged_single"]) == single_n,
		"tree walk agrees with the loader's split counters",
		"walk_mm=%d want=%d walk_single=%d want=%d" % [
			int(walk["tagged_mm"]), mm_n, int(walk["tagged_single"]), single_n])
	_check(int(walk["untagged_neg"]) == 0,
		"no negative-determinant draw node hides in an untagged batch",
		"untagged_neg=%d gc_native=%d" % [int(walk["untagged_neg"]), int(walk["gc_native_neg"])])
	_check(int(walk["tagged_mm"]) + int(walk["tagged_single"]) == draw_bases,
		"every draw-census mirrored instance is tagged",
		"walk=%d bases=%d" % [int(walk["tagged_mm"]) + int(walk["tagged_single"]), draw_bases])
	_check(int(walk["tagged_neg_nodes"]) == split_n,
		"one negative node per split item (no hidden extra split)",
		"nodes=%d splits=%d" % [int(walk["tagged_neg_nodes"]), split_n])
	_check(int(walk["split_checked"]) == split_n and bool(walk["split_source_ok"]),
		"every split item apportions pos+neg source counts exactly once",
		"checked=%d splits=%d ok=%s" % [
			int(walk["split_checked"]), split_n, str(walk["split_source_ok"])])
	_check(int(walk["cull_front_instances"]) == int(res.get("mirrored_cull_front", -1)),
		"cull-front counter is per-instance, not per-node",
		"walk=%d counter=%d" % [
			int(walk["cull_front_instances"]), int(res.get("mirrored_cull_front", -1))])
	_check(int(walk["cull_disabled_instances"]) == int(res.get("mirrored_cull_disabled", -1)),
		"cull-disabled counter is per-instance, not per-node",
		"walk=%d counter=%d" % [
			int(walk["cull_disabled_instances"]), int(res.get("mirrored_cull_disabled", -1))])
	_check((walk["baked_unique"] as Dictionary).size() == int(res.get("mirrored_mesh_count", -1)),
		"baked-variant counter is per unique mesh, not per node",
		"walk=%d counter=%d" % [
			(walk["baked_unique"] as Dictionary).size(), int(res.get("mirrored_mesh_count", -1))])
	if draw_bases > 0:
		_check(int(walk["baked_nodes"]) + int(walk["cull_front_nodes"]) + int(walk["cull_disabled_nodes"]) + int(walk["native_nodes"]) > 0,
			"every tagged node carries a known mirror mode",
			"baked=%d cull_front=%d cull_disabled=%d native=%d" % [
				int(walk["baked_nodes"]), int(walk["cull_front_nodes"]),
				int(walk["cull_disabled_nodes"]), int(walk["native_nodes"])])
	print("MIRROR_LOAD paths=%d authored_records_neg=%d transform_bases=%d draw_bases=%d mm=%d single=%d split=%d cull_front=%d cull_disabled=%d baked_variants=%d baked_bytes=%d unbaked=%d walk_mm=%d walk_single=%d walk_baked_nodes=%d untagged_neg=%d gc_native_neg=%d src_sum=%d perf_instances=%d" % [
		paths.size(),
		authored_neg,
		int(res.get("mirrored_transform_bases", -1)),
		draw_bases,
		mm_n,
		single_n,
		split_n,
		int(res.get("mirrored_cull_front", -1)),
		int(res.get("mirrored_cull_disabled", -1)),
		int(res.get("mirrored_mesh_count", -1)),
		int(res.get("mirrored_mesh_bytes", -1)),
		int(res.get("mirrored_unbaked", -1)),
		int(walk["tagged_mm"]),
		int(walk["tagged_single"]),
		int(walk["baked_nodes"]),
		int(walk["untagged_neg"]),
		int(walk["gc_native_neg"]),
		src_sum,
		int(census.get("mesh_instances", -1)),
	])
	host.queue_free()


func _walk_mirror_nodes(host: Node3D) -> Dictionary:
	var out: Dictionary = {
		"tagged_mm": 0,
		"tagged_single": 0,
		"tagged_neg_nodes": 0,
		"split_checked": 0,
		"split_source_ok": true,
		"untagged_neg": 0,
		"gc_native_neg": 0,
		"baked_nodes": 0,
		"cull_front_nodes": 0,
		"cull_disabled_nodes": 0,
		"native_nodes": 0,
		"cull_front_instances": 0,
		"cull_disabled_instances": 0,
		"native_instances": 0,
		"baked_unique": {},
	}
	var nodes: Array[Node] = host.find_children("*", "GeometryInstance3D", true, false)
	for node_v: Node in nodes:
		var gi: GeometryInstance3D = node_v as GeometryInstance3D
		if gi == null:
			continue
		var tagged: bool = bool(gi.get_meta("mirror_neg", false))
		var mode: String = str(gi.get_meta("mirror_mode", ""))
		var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			var mm: MultiMesh = mmi.multimesh
			if not tagged:
				# A headless MultiMesh stores its instance buffer in the dummy
				# RenderingServer, which returns identity transforms; the split
				# coverage is proven by the counters/partition, not this walk.
				continue
			out["tagged_mm"] = int(out["tagged_mm"]) + mm.instance_count
			_note_split_accounting(gi, out)
			_check(int(gi.get_meta("mirror_instances", -1)) == mm.instance_count,
				"tagged MultiMesh meta count matches instance_count",
				"meta=%d instances=%d" % [int(gi.get_meta("mirror_instances", -1)), mm.instance_count])
			if mode == "baked":
				out["baked_nodes"] = int(out["baked_nodes"]) + 1
				var bm: Mesh = mm.mesh
				_check(bm != null and bool(bm.get_meta("mirror_baked", false)),
					"baked MultiMesh uses the baked ArrayMesh",
					"mesh=%s" % (bm.resource_name if bm != null else "null"))
				if bm != null:
					(out["baked_unique"] as Dictionary)[bm.get_instance_id()] = true
			elif mode == "cull_front":
				out["cull_front_nodes"] = int(out["cull_front_nodes"]) + 1
				out["cull_front_instances"] = int(out["cull_front_instances"]) + mm.instance_count
				_check(_effective_cull(gi, 0) == BaseMaterial3D.CULL_FRONT,
					"cull-front batch material is CULL_FRONT",
					"cull=%d" % _effective_cull(gi, 0))
			elif mode == "cull_disabled":
				out["cull_disabled_nodes"] = int(out["cull_disabled_nodes"]) + 1
				out["cull_disabled_instances"] = int(out["cull_disabled_instances"]) + mm.instance_count
				_check(_effective_cull(gi, 0) == BaseMaterial3D.CULL_DISABLED,
					"cull-disabled batch is two-sided",
					"cull=%d" % _effective_cull(gi, 0))
			else:
				_check(false, "MultiMesh mirror mode is known", "mode=%s" % mode)
			continue
		var mi: MeshInstance3D = gi as MeshInstance3D
		if mi == null:
			continue
		if not tagged and (gi.has_meta("gc_role") or gi.has_meta("gc_owner")):
			# Mirrored GC overlays built by _build_gc_layers() are standalone
			# MeshInstance3D nodes outside the draw-item census; Godot
			# compensates them natively. A *tagged* bookcase glass pane also
			# carries gc_owner/gc_static_leaf after the owner bind, so the
			# exclusion must never swallow a tagged mirror node.
			if mi.transform.basis.determinant() < 0.0:
				out["gc_native_neg"] = int(out["gc_native_neg"]) + 1
			continue
		if not tagged:
			if mi.transform.basis.determinant() < 0.0:
				out["untagged_neg"] = int(out["untagged_neg"]) + 1
			continue
		out["tagged_single"] = int(out["tagged_single"]) + 1
		_note_split_accounting(gi, out)
		if mode == "native":
			out["native_nodes"] = int(out["native_nodes"]) + 1
			out["native_instances"] = int(out["native_instances"]) + 1
			_check(mi.transform.basis.determinant() < 0.0,
				"native standalone keeps the authored negative basis",
				"det=%.3f" % mi.transform.basis.determinant())
		elif mode == "baked":
			out["baked_nodes"] = int(out["baked_nodes"]) + 1
			_check(mi.transform.basis.determinant() > 0.0,
				"baked standalone basis is positive",
				"det=%.3f" % mi.transform.basis.determinant())
			_check(mi.mesh != null and bool(mi.mesh.get_meta("mirror_baked", false)),
				"baked standalone uses the baked mesh",
				"mesh=%s" % (mi.mesh.resource_name if mi.mesh != null else "null"))
			if mi.mesh != null:
				(out["baked_unique"] as Dictionary)[mi.mesh.get_instance_id()] = true
		elif mode == "cull_front":
			out["cull_front_nodes"] = int(out["cull_front_nodes"]) + 1
			out["cull_front_instances"] = int(out["cull_front_instances"]) + 1
			_check(_effective_cull(mi, 0) == BaseMaterial3D.CULL_FRONT,
				"standalone cull-front material is CULL_FRONT",
				"cull=%d" % _effective_cull(mi, 0))
		elif mode == "cull_disabled":
			out["cull_disabled_nodes"] = int(out["cull_disabled_nodes"]) + 1
			out["cull_disabled_instances"] = int(out["cull_disabled_instances"]) + 1
			_check(_effective_cull(mi, 0) == BaseMaterial3D.CULL_DISABLED,
				"standalone cull-disabled material is two-sided",
				"cull=%d" % _effective_cull(mi, 0))
		else:
			_check(false, "standalone mirror mode is known", "mode=%s" % mode)
	return out


## P4.2: every tagged negative node records the item's full source map and the
## pos/neg apportionment. Assert pos + neg == item and that the node's own
## `source_counts` meta is the neg part, so a future split cannot repeat the
## PERF_CENSUS double count.
func _note_split_accounting(gi: GeometryInstance3D, out: Dictionary) -> void:
	out["tagged_neg_nodes"] = int(out["tagged_neg_nodes"]) + 1
	var item_v: Variant = gi.get_meta("mirror_item_source_counts", null)
	var pos_v: Variant = gi.get_meta("mirror_pos_source_counts", null)
	var neg_v: Variant = gi.get_meta("mirror_neg_source_counts", null)
	var own_v: Variant = gi.get_meta("source_counts", null)
	if not (item_v is Dictionary) or not (pos_v is Dictionary) or not (neg_v is Dictionary):
		out["split_source_ok"] = false
		return
	out["split_checked"] = int(out["split_checked"]) + 1
	if not _dicts_add_equal(pos_v as Dictionary, neg_v as Dictionary, item_v as Dictionary):
		out["split_source_ok"] = false
		print("MIRROR_SPLIT_ACCOUNT_FAIL item=", item_v, " pos=", pos_v, " neg=", neg_v, " own=", own_v)
	if not (own_v is Dictionary) or (own_v as Dictionary) != (neg_v as Dictionary):
		out["split_source_ok"] = false
