extends SceneTree
## Suite 83: review-map baker.
##
## Part 1 unit-tests the tagger on synthetic nodes (no assets, no GPU).
## Part 2 runs the real headless CLI on thieves_den (285 meshes) into
## user://review_test and asserts exit 0, the manifest schema, consistency
## checks, and that a baked per-sublevel scene loads with tagged nodes.
##
## Run: tools/godot --headless --path game --script res://tests/test_review_baker.gd
## Budget: ~6 s (child engine startup ~1 s + Den load/save ~4.5 s).

var fails: int = 0


func _check(cond: bool, ok: String, fail: String) -> void:
	if cond:
		print("PASS: ", ok)
	else:
		printerr("FAIL: ", fail)
		fails += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var tagger: GDScript = load("res://addons/tat2_review/review_tagger.gd") as GDScript
	var filters: GDScript = load("res://addons/tat2_review/review_filters.gd") as GDScript
	if tagger == null or filters == null:
		printerr("FAIL: review addon scripts did not load")
		print("REVIEW_TEST SUMMARY: fails=1")
		quit(1)
		return

	var tag_root: Node3D = Node3D.new()
	tag_root.name = "ReviewTagFixture"
	root.add_child(tag_root)

	# 83.0 beam_lines: authored LightBeam mesh path.
	var beam_a: MeshInstance3D = MeshInstance3D.new()
	beam_a.name = "BeamByPath"
	beam_a.mesh = BoxMesh.new()
	beam_a.set_meta("ue_mesh", "/Game/Art/Effects/LightBeam/SM_LightBeam")
	tag_root.add_child(beam_a)
	var ta: Dictionary = tagger.classify_node(beam_a, "Unit")
	_check(ta["review_kind"] == "mesh" and ta["review_issue"] == "beam_lines",
		"83.0 LightBeam mesh path -> beam_lines",
		"beam path tag failed: " + str(ta))

	# 83.1 beam_lines: tat_beam ShaderMaterial (the loader's MI_LightBeam_SM path).
	var beam_b: MeshInstance3D = MeshInstance3D.new()
	beam_b.name = "BeamByMaterial"
	beam_b.mesh = BoxMesh.new()
	var beam_mat: ShaderMaterial = ShaderMaterial.new()
	beam_mat.shader = load("res://src/core/tat_beam.gdshader") as Shader
	beam_b.set_surface_override_material(0, beam_mat)
	tag_root.add_child(beam_b)
	var tb: Dictionary = tagger.classify_node(beam_b, "Unit")
	_check(tb["review_issue"] == "beam_lines", "83.1 tat_beam material -> beam_lines", "beam material tag failed: " + str(tb))

	# 83.2 world_label (Label3D / billboard Sprite3D).
	var label: Label3D = Label3D.new()
	label.name = "FloatingLabel"
	label.text = "PICK LOCK"
	tag_root.add_child(label)
	var tl: Dictionary = tagger.classify_node(label, "Unit")
	_check(tl["review_issue"] == "world_label", "83.2 Label3D -> world_label", "label tag failed: " + str(tl))

	# 83.3 emissive_plate (StandardMaterial3D energy > 0.5).
	var plate: MeshInstance3D = MeshInstance3D.new()
	plate.name = "EmissivePlate"
	plate.mesh = BoxMesh.new()
	var emat: StandardMaterial3D = StandardMaterial3D.new()
	emat.emission_enabled = true
	emat.emission = Color(0.1, 0.9, 1.0)
	emat.emission_energy_multiplier = 2.5
	plate.set_surface_override_material(0, emat)
	tag_root.add_child(plate)
	var te: Dictionary = tagger.classify_node(plate, "Unit")
	_check(te["review_issue"] == "emissive_plate", "83.3 emissive StandardMaterial3D -> emissive_plate", "emissive tag failed: " + str(te))

	# 83.4 light / collision / multimesh / occluder / fog kinds.
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "UnitLight"
	tag_root.add_child(light)
	_check(tagger.classify_node(light, "Unit")["review_kind"] == "light", "83.4 OmniLight3D -> light", "light kind failed")
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "UnitCollision"
	tag_root.add_child(body)
	var tcol: Dictionary = tagger.classify_node(body, "Unit")
	_check(tcol["review_kind"] == "collision" and tcol["review_issue"] == "collision_only",
		"83.5 StaticBody3D -> collision + collision_only", "collision tag failed: " + str(tcol))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "UnitMultiMesh"
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 3
	mmi.multimesh = mm
	tag_root.add_child(mmi)
	_check(tagger.classify_node(mmi, "Unit")["review_kind"] == "multimesh", "83.6 MultiMeshInstance3D -> multimesh", "multimesh kind failed")
	var occ: OccluderInstance3D = OccluderInstance3D.new()
	occ.name = "UnitOccluder"
	tag_root.add_child(occ)
	_check(tagger.classify_node(occ, "Unit")["review_kind"] == "occluder", "83.7 OccluderInstance3D -> occluder", "occluder kind failed")
	var fog: FogVolume = FogVolume.new()
	fog.name = "UnitFog"
	tag_root.add_child(fog)
	_check(tagger.classify_node(fog, "Unit")["review_kind"] == "fog", "83.8 FogVolume -> fog", "fog kind failed")

	# 83.9 apply_tags writes on every node; collect_stats counts; filters match.
	tagger.apply_tags(tag_root, "Unit")
	var tagged_everywhere: bool = true
	var stack: Array[Node] = [tag_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if str(n.get_meta("review_sublevel", "")) != "Unit" or not n.has_meta("review_kind"):
			tagged_everywhere = false
		for c: Node in n.get_children():
			stack.push_back(c)
	_check(tagged_everywhere, "83.9 every node carries review_sublevel + review_kind", "apply_tags missed a node")
	var stats: Dictionary = tagger.collect_stats(tag_root)
	_check(int(stats["lights"]) == 1 and int(stats["collision_bodies"]) == 1 and int((stats["issues"] as Dictionary).get("beam_lines", 0)) == 2,
		"83.10 collect_stats: 1 light, 1 collision body, 2 beams",
		"collect_stats mismatch: " + str(stats))
	_check(filters.matches(beam_a, "Beams") and filters.matches(light, "Lighting") and filters.matches(body, "Collision"),
		"83.11 review_filters honour issue/kind metadata", "filters mismatch")
	_check(not filters.matches(beam_a, "Decals"), "83.12 filters do not over-match", "filter over-matched")
	tag_root.free()

	# --- Part 2: real bake on the Den -------------------------------------
	var project_dir: String = ProjectSettings.globalize_path("res://")
	var repo_dir: String = project_dir.path_join("..").simplify_path()
	var baker_script: String = repo_dir.path_join("tools/bake_review_map.gd")
	_check(FileAccess.file_exists(baker_script), "83.13 baker CLI exists at tools/bake_review_map.gd", "missing " + baker_script)
	var out_dir: String = "user://review_test"
	_clear_dir(out_dir)
	var args: PackedStringArray = [
		"--headless",
		"--path", project_dir,
		"--script", baker_script,
		"--",
		"--map=thieves_den",
		"--out=" + out_dir,
	]
	var started: int = Time.get_ticks_msec()
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var elapsed: int = Time.get_ticks_msec() - started
	var text: String = "\n".join(PackedStringArray(output))
	_check(code == 0, "83.14 thieves_den bake exit=0 (%d ms)" % elapsed, "bake exit=%d\n%s" % [code, text.right(2000)])
	_check(text.find("REVIEW_BAKE summary") >= 0 and text.find("status=ok") >= 0,
		"83.15 REVIEW_BAKE summary status=ok", "summary missing\n" + text.right(2000))

	var manifest_path: String = out_dir.path_join("review_manifest.json")
	var manifest_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	_check(manifest_v is Dictionary, "83.16 manifest parses as JSON", "manifest missing/invalid: " + manifest_path)
	if manifest_v is Dictionary:
		var m: Dictionary = manifest_v as Dictionary
		var required: Array[String] = ["git_sha", "map", "seed", "resolution", "sublevels", "totals", "issues", "bookmarks", "scenes", "checks", "ok"]
		var missing: Array[String] = []
		for k: String in required:
			if not m.has(k):
				missing.append(k)
		_check(missing.is_empty(), "83.17 manifest schema keys present", "missing keys: " + str(missing))
		_check(str(m.get("map", "")) == "thieves_den" and bool(m.get("ok", false)), "83.18 manifest map/status", "map/ok wrong: " + str(m.get("map")) + " " + str(m.get("ok")))
		var totals: Dictionary = m.get("totals", {})
		_check(int(totals.get("mesh_instances", 0)) > 0 and int(totals.get("nodes", 0)) > 0,
			"83.19 manifest counts non-zero (mesh_instances=%d nodes=%d)" % [int(totals.get("mesh_instances", 0)), int(totals.get("nodes", 0))],
			"counts zero: " + str(totals))
		var subs: Array = m.get("sublevels", [])
		_check(subs.size() >= 3, "83.20 all Den sublevels baked (%d)" % subs.size(), "sublevels=%d" % subs.size())
		var checks_ok: bool = true
		for stem: String in (m.get("checks", {}) as Dictionary).keys():
			for name: String in ((m.get("checks", {}) as Dictionary)[stem] as Dictionary).keys():
				if not bool((((m.get("checks", {}) as Dictionary)[stem] as Dictionary)[name] as Dictionary).get("ok", false)):
					checks_ok = false
		_check(checks_ok, "83.21 loader/tag consistency checks all pass", "consistency check failed: " + str(m.get("checks", {})))
		var scene_path: String = ""
		for s: Dictionary in m.get("scenes", []):
			if str(s.get("kind", "")) == "sublevel":
				scene_path = str(s.get("path", ""))
				break
		_check(scene_path != "" and ResourceLoader.exists(scene_path), "83.22 baked sublevel scene exists (%s)" % scene_path.get_file(), "no sublevel scene in manifest")
		if scene_path != "" and ResourceLoader.exists(scene_path):
			var ps: PackedScene = load(scene_path) as PackedScene
			var inst: Node = ps.instantiate() if ps != null else null
			var ncount: int = _count_nodes(inst) if inst != null else 0
			var tagged: bool = _has_tagged_node(inst) if inst != null else false
			_check(ncount > 0 and tagged, "83.23 baked scene loads with tagged nodes (nodes=%d)" % ncount, "scene node count/tag failed: %d %s" % [ncount, str(tagged)])
			if inst != null:
				inst.free()

	print("REVIEW_TEST SUMMARY: fails=", fails, " bake_ms=", elapsed)
	quit(0 if fails == 0 else 1)


func _clear_dir(path: String) -> void:
	var abs: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f: String in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(f))
	for d: String in DirAccess.get_directories_at(abs):
		_clear_dir(path.path_join(d))


func _count_nodes(node: Node) -> int:
	if node == null:
		return 0
	var n: int = 1
	for c: Node in node.get_children():
		n += _count_nodes(c)
	return n


func _has_tagged_node(node: Node) -> bool:
	if node == null:
		return false
	if node.has_meta("review_kind") and node.has_meta("review_sublevel"):
		return true
	for c: Node in node.get_children():
		if _has_tagged_node(c):
			return true
	return false
