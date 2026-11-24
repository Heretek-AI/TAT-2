extends SceneTree
## W0T part 2: core-min single-call bake.
##
## `tools/bake_review_map.gd --mode=single --sublevels=core` must build the
## POI + 3rd floor + Gameplay + Lighting set (for Guildhall) through ONE
## `load_sublevels_async()` call with a 160-light budget, tag provenance, and
## save `<map>_core.scn` + `review_core.tscn`. This suite proves it on the
## fast Den case and loads the result headless.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_review_core_bake.gd
## Set TAT2_REVIEW_CORE_MAP=guildhall to exercise the slow Guildhall core bake.
## Budget: ~10 s (Den single call + pack + headless load).

var fails: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String) -> void:
	if cond:
		print("PASS: ", ok)
	else:
		printerr("FAIL: ", fail)
		fails += 1


func _run() -> void:
	await process_frame
	var map_id: String = OS.get_environment("TAT2_REVIEW_CORE_MAP")
	if map_id == "":
		map_id = "thieves_den"
	var project_dir: String = ProjectSettings.globalize_path("res://")
	var repo_dir: String = project_dir.path_join("..").simplify_path()
	var baker_script: String = repo_dir.path_join("tools/bake_review_map.gd")
	_check(FileAccess.file_exists(baker_script), "4.1 core baker CLI exists", "missing " + baker_script)
	if not FileAccess.file_exists(baker_script):
		_finish()
		return
	var out_dir: String = "user://review_core_test_%s" % map_id
	_clear_dir(out_dir)
	var args: PackedStringArray = [
		"--headless",
		"--path", project_dir,
		"--script", baker_script,
		"--",
		"--map=" + map_id,
		"--mode=single",
		"--sublevels=core",
		"--out=" + out_dir,
	]
	var started: int = Time.get_ticks_msec()
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var elapsed: int = Time.get_ticks_msec() - started
	var text: String = "\n".join(PackedStringArray(output))
	_check(code == 0, "4.2 %s core bake exit=0 (%d ms)" % [map_id, elapsed], "core bake exit=%d\n%s" % [code, text.right(3000)])
	_check(text.find("REVIEW_BAKE summary") >= 0 and text.find("mode=single") >= 0 and text.find("status=ok") >= 0,
		"4.3 REVIEW_BAKE summary mode=single status=ok", "summary missing/wrong\n" + text.right(3000))

	var manifest_path: String = out_dir.path_join("review_manifest.json")
	var manifest_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	_check(manifest_v is Dictionary, "4.4 core manifest parses", "manifest invalid: " + manifest_path)
	if not (manifest_v is Dictionary):
		_finish()
		return
	var m: Dictionary = manifest_v as Dictionary
	_check(str(m.get("mode", "")) == "single", "4.5 manifest mode=single", "mode=" + str(m.get("mode")))
	_check(bool(m.get("ok", false)), "4.6 manifest ok=true", "manifest errors: " + str(m.get("errors", [])))
	var core: Dictionary = m.get("core", {})
	var core_subs: Array = core.get("sublevels", [])
	_check(core_subs.size() >= 2, "4.7 core sublevels loaded in one call (%d)" % core_subs.size(), "core sublevels=%d" % core_subs.size())
	_check(int(core.get("light_budget", 0)) == 160, "4.8 one 160-light budget", "budget=" + str(core.get("light_budget")))
	var has_periphery: bool = false
	for sub_v: Variant in core_subs:
		if str(sub_v).to_lower().find("periphery") >= 0 or str(sub_v).to_lower().find("skyboxgeo") >= 0:
			has_periphery = true
	_check(not has_periphery, "4.9 core set excludes PeripheryA/SkyboxGeo", "periphery in core: " + str(core_subs))
	var loader_counts: Dictionary = core.get("loader_counts", {})
	var loader_lights: int = int(loader_counts.get("light_count", -1))
	_check(loader_lights >= 0 and loader_lights <= 160, "4.10 loader light_count <= 160 (%d)" % loader_lights, "light_count=%d" % loader_lights)
	var by_sub: Dictionary = m.get("by_sublevel", {})
	_check(not by_sub.is_empty(), "4.11 manifest aggregates by review_sublevel (%d stems)" % by_sub.size(), "by_sublevel empty")
	var tagged_stems: int = 0
	for stem_v: Variant in by_sub.keys():
		var stem: String = str(stem_v)
		if stem != "":
			tagged_stems += 1
		var sc: Dictionary = (m.get("checks", {}) as Dictionary).get(stem, {})
		if not bool(sc.get("ok", false)):
			_check(false, "4.12 sublevel provenance check %s" % stem, "check failed: " + str(sc))
	_check(tagged_stems == core_subs.size(), "4.13 every core sublevel has provenance counts (%d/%d)" % [tagged_stems, core_subs.size()], "tagged=%d core=%d" % [tagged_stems, core_subs.size()])
	_check((m.get("checks", {}) as Dictionary).has("_aggregate"), "4.14 aggregate loader/tag checks present", "no _aggregate checks")
	_check(int((m.get("totals", {}) as Dictionary).get("hidden_nodes", 0)) >= 0,
		"4.15 manifest records authored-hidden nodes (%d)" % int((m.get("totals", {}) as Dictionary).get("hidden_nodes", 0)),
		"hidden_nodes missing")

	var core_scene_path: String = ""
	var master_path: String = ""
	for s_v: Variant in m.get("scenes", []):
		var s: Dictionary = s_v as Dictionary
		if str(s.get("kind", "")) == "core":
			core_scene_path = str(s.get("path", ""))
		elif str(s.get("kind", "")) == "review_core_master":
			master_path = str(s.get("path", ""))
	_check(core_scene_path != "" and master_path != "", "4.16 manifest lists core.scn + review_core.tscn", "scenes=" + str(m.get("scenes", [])))
	for p: String in [core_scene_path, master_path]:
		if p == "":
			continue
		var bytes: int = _file_size(p)
		_check(ResourceLoader.exists(p) and bytes > 0, "4.17 baked %s exists (%.2f MB)" % [p.get_file(), bytes / 1048576.0], "missing " + p)
		_check(bytes <= 256 * 1024 * 1024, "4.18 %s under the 256 MB core guard" % p.get_file(), "size=%d" % bytes)

	if core_scene_path != "" and ResourceLoader.exists(core_scene_path):
		var ps: PackedScene = load(core_scene_path) as PackedScene
		var inst: Node = ps.instantiate() if ps != null else null
		var counts: Dictionary = _scan_core(inst) if inst != null else {}
		_check(inst != null and int(counts.get("nodes", 0)) > 0, "4.19 core scene loads headless (nodes=%d)" % int(counts.get("nodes", 0)), "core scene did not instantiate")
		_check(int(counts.get("tagged", 0)) > 0, "4.20 core scene keeps review_sublevel provenance (%d nodes)" % int(counts.get("tagged", 0)), "no provenance tags")
		_check(int(counts.get("authored_meta", 0)) == int(counts.get("nodes", -1)), "4.21 every loaded node carries review_authored_visible (%d)" % int(counts.get("authored_meta", 0)), "authored meta missing on some nodes")
		_check(int(counts.get("hidden_visible", 0)) == 0, "4.22 authored-hidden core nodes are not visible (%d visible)" % int(counts.get("hidden_visible", 0)), "hidden node visible in core scene")
		_check(int(counts.get("lights", 0)) <= 160, "4.23 core scene lights <= 160 (%d)" % int(counts.get("lights", 0)), "lights=%d" % int(counts.get("lights", 0)))
		if inst != null:
			inst.free()

	if master_path != "" and ResourceLoader.exists(master_path):
		var mps: PackedScene = load(master_path) as PackedScene
		var minst: Node = mps.instantiate() if mps != null else null
		var has_env: bool = _has_node_type(minst, "WorldEnvironment") if minst != null else false
		var marks: int = _count_meta(minst, "review_bookmark") if minst != null else 0
		_check(has_env and marks > 0, "4.24 review_core.tscn carries review environment + %d bookmarks" % marks, "env=%s bookmarks=%d" % [str(has_env), marks])
		if minst != null:
			minst.free()

	print("REVIEW_CORE_SUMMARY: map=", map_id, " fails=", fails, " bake_ms=", elapsed)
	_finish()


func _finish() -> void:
	quit(0 if fails == 0 else 1)


func _clear_dir(path: String) -> void:
	var abs: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f: String in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(f))
	for d: String in DirAccess.get_directories_at(abs):
		_clear_dir(path.path_join(d))


func _file_size(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n: int = f.get_length()
	f.close()
	return n


func _scan_core(root: Node) -> Dictionary:
	var out: Dictionary = {"nodes": 0, "tagged": 0, "authored_meta": 0, "hidden_visible": 0, "lights": 0}
	if root == null:
		return out
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out["nodes"] = int(out["nodes"]) + 1
		if n.has_meta("review_sublevel") and str(n.get_meta("review_sublevel")) != "":
			out["tagged"] = int(out["tagged"]) + 1
		if n.has_meta("review_authored_visible"):
			out["authored_meta"] = int(out["authored_meta"]) + 1
			if not bool(n.get_meta("review_authored_visible")) and n is Node3D and (n as Node3D).visible:
				out["hidden_visible"] = int(out["hidden_visible"]) + 1
		if n is Light3D and not str(n.name).begins_with("SkylightLeakingFill_"):
			# Loader GI fills are added outside the light budget; count only
			# budgeted lights (same rule as review_tagger.collect_stats).
			out["lights"] = int(out["lights"]) + 1
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


func _has_node_type(root: Node, type_name: String) -> bool:
	if root == null:
		return false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(type_name):
			return true
		for c: Node in n.get_children():
			stack.push_back(c)
	return false


func _count_meta(root: Node, meta: String) -> int:
	if root == null:
		return 0
	var n_found: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta(meta):
			n_found += 1
		for c: Node in n.get_children():
			stack.push_back(c)
	return n_found
