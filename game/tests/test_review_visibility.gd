extends SceneTree
## W0T part 1: review visibility truth.
##
## The bug: review mode/dock set `visible = not hidden_by_toggle` on every node,
## which unhid authored `bHiddenInGame` fixtures (Guildhall POI/3rd floor
## floating cyan blobs). The loader is right; the review UI was wrong.
##
## This suite gates:
##   * the tagger captures `review_authored_visible` before any toggle;
##   * Filters.visible_after_toggles keeps authored-hidden nodes hidden with
##     every show-toggle on, and with Beams/Emissive off;
##   * the real in-game review `_apply_toggles()` and the editor dock
##     `_apply_to_scene()` both obey that rule;
##   * the `Hidden in game` toggle (default off) is the only reveal path;
##   * real `SM_DonutShell` / `SM_Sphere4Count` fixtures loaded through the real
##     LevelLoader stay hidden (tiny two-mesh fixture, not the whole map);
##   * the Guildhall authored-hidden accounting: 697 records in the review's
##     resolved sublevels, 710 across the whole Guildhall family (the four
##     contract-scoped facade/teleporter files add 13).
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_review_visibility.gd
## Budget: ~5 s (two real meshes through the loader; no GPU, no full map).

const Tagger: GDScript = preload("res://addons/tat2_review/review_tagger.gd")
const Filters: GDScript = preload("res://addons/tat2_review/review_filters.gd")
const MapData: GDScript = preload("res://addons/tat2_review/review_map_data.gd")
const ReviewEnvironment: GDScript = preload("res://addons/tat2_review/review_environment.gd")
const POI_JSON: String = "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json"
const THIRD_JSON: String = "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.tatlevel.json"

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
	_test_synthetic_formula()
	await _test_real_loader_fixture()
	_test_authored_hidden_accounting()
	_test_review_environment()
	print("REVIEW_VISIBILITY_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


func _all_toggles(hidden_in_game: bool = false) -> Dictionary:
	var toggles: Dictionary = {}
	for t: String in Filters.all_toggles():
		toggles[t] = true
	toggles[Filters.AUTHORED_HIDDEN_TOGGLE] = hidden_in_game
	return toggles


func _test_synthetic_formula() -> void:
	var host: Node3D = Node3D.new()
	host.name = "VisibilityFormula"
	root.add_child(host)
	var authored_hidden: MeshInstance3D = MeshInstance3D.new()
	authored_hidden.name = "AuthoredHidden"
	authored_hidden.mesh = BoxMesh.new()
	authored_hidden.visible = false
	host.add_child(authored_hidden)
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.name = "Beam"
	beam.mesh = BoxMesh.new()
	beam.set_meta("ue_mesh", "/Game/Art/Effects/LightBeam/SM_LightBeam")
	host.add_child(beam)
	var plate: MeshInstance3D = MeshInstance3D.new()
	plate.name = "Plate"
	plate.mesh = BoxMesh.new()
	var emat: StandardMaterial3D = StandardMaterial3D.new()
	emat.emission_enabled = true
	emat.emission = Color(0.1, 0.9, 1.0)
	emat.emission_energy_multiplier = 2.5
	plate.set_surface_override_material(0, emat)
	host.add_child(plate)
	Tagger.apply_tags(host, "Unit")

	_check(not Filters.authored_visible(authored_hidden), "1.1 tagger records authored-hidden as visible=false", "review_authored_visible missing/true")
	_check(Filters.authored_visible(beam), "1.2 tagger records visible nodes as authored-visible", "beam authored_visible false")

	var all_on: Dictionary = _all_toggles(false)
	_check(not Filters.visible_after_toggles(authored_hidden, all_on), "1.3 all show-toggles on: authored-hidden stays hidden", "authored-hidden was revealed by show-toggles")
	_check(Filters.visible_after_toggles(beam, all_on) and Filters.visible_after_toggles(plate, all_on), "1.4 all show-toggles on: normal nodes visible", "normal node hidden")
	var beams_off: Dictionary = _all_toggles(false)
	beams_off["Beams"] = false
	beams_off["Emissive plates"] = false
	_check(not Filters.visible_after_toggles(authored_hidden, beams_off), "1.5 Beams/Emissive off: authored-hidden still hidden", "authored-hidden revealed by Beams/Emissive toggle")
	_check(not Filters.visible_after_toggles(beam, beams_off) and not Filters.visible_after_toggles(plate, beams_off), "1.6 Beams/Emissive off: beam and plate hidden", "beam/plate show-toggle failed")
	var reveal: Dictionary = _all_toggles(true)
	_check(Filters.visible_after_toggles(authored_hidden, reveal), "1.7 Hidden in game toggle reveals the authored fixture", "reveal toggle failed")

	# The in-game review path.
	var review: Node = (load("res://src/ui/review_mode.gd") as GDScript).new()
	review.set("_world_root", host)
	review.set("_toggles", reveal)
	review.call("_apply_toggles")
	_check(authored_hidden.visible and beam.visible and plate.visible, "1.8 review_mode._apply_toggles: reveal-all state", "review mode reveal failed")
	var review_hide: Dictionary = _all_toggles(false)
	review.set("_toggles", review_hide)
	review.call("_apply_toggles")
	_check(not authored_hidden.visible, "1.9 review_mode._apply_toggles: authored-hidden stays hidden with all toggles on", "review mode unhid authored fixture")
	review.free()

	# The editor dock path (state comes from root metadata).
	var dock_root: Node3D = Node3D.new()
	dock_root.name = "DockRoot"
	root.add_child(dock_root)
	var dock_node: MeshInstance3D = MeshInstance3D.new()
	dock_node.name = "AuthoredHiddenDock"
	dock_node.mesh = BoxMesh.new()
	dock_node.set_meta("review_authored_visible", false)
	dock_node.visible = true  # simulate the old bug: editor scene starts shown
	dock_root.add_child(dock_node)
	var dock: Node = (load("res://addons/tat2_review/dock.gd") as GDScript).new()
	dock_root.set_meta("review_toggles", _all_toggles(false))
	dock.call("_apply_to_scene", dock_root)
	_check(not dock_node.visible, "1.10 dock._apply_to_scene hides authored-hidden with Hidden in game off", "dock unhid authored fixture")
	dock_root.set_meta("review_toggles", _all_toggles(true))
	dock.call("_apply_to_scene", dock_root)
	_check(dock_node.visible, "1.11 dock._apply_to_scene reveals only when Hidden in game is on", "dock reveal failed")
	dock.free()
	host.free()
	dock_root.free()


func _test_real_loader_fixture() -> void:
	if not FileAccess.file_exists(POI_JSON) or not FileAccess.file_exists(THIRD_JSON):
		print("SKIP: generated Guildhall POI JSONs absent; real-fixture checks skipped")
		return
	var donut: Dictionary = _first_hidden_mesh(THIRD_JSON, "SM_DonutShell")
	var sphere: Dictionary = _first_hidden_mesh(POI_JSON, "SM_Sphere4Count")
	_check(not donut.is_empty(), "2.1 found authored-hidden SM_DonutShell in POI_3rdFloor", "no hidden SM_DonutShell entry")
	_check(not sphere.is_empty(), "2.2 found authored-hidden SM_Sphere4Count in POI", "no hidden SM_Sphere4Count entry")
	if donut.is_empty() or sphere.is_empty():
		return
	var fixture_path: String = "user://review_visibility_fixture.tatlevel.json"
	var fixture: Dictionary = {
		"source": "W0T visibility fixture",
		"meshes": [donut, sphere],
	}
	var f: FileAccess = FileAccess.open(fixture_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(fixture))
	f.close()
	var host: Node3D = Node3D.new()
	host.name = "VisibilityFixtureHost"
	root.add_child(host)
	var ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ll)
	await ll.call("load_sublevels_async", [fixture_path], host, null, 160, false)
	Tagger.apply_tags(host)
	var hidden: Array[Node3D] = _find_ue(host, ["SM_DonutShell", "SM_Sphere4Count"])
	_check(hidden.size() >= 2, "2.3 real loader built hidden fixtures (nodes=%d)" % hidden.size(), "hidden fixture nodes missing: %d" % hidden.size())
	var all_hidden: bool = true
	var authored_false: bool = true
	for n: Node3D in hidden:
		if n.visible:
			all_hidden = false
		if not n.has_meta("review_authored_visible") or bool(n.get_meta("review_authored_visible")):
			authored_false = false
	_check(all_hidden and authored_false, "2.4 real loader hidden fixtures load visible=false with authored meta", "real fixture visible/authored meta wrong")
	var toggle_names: Array[String] = ["Beams", "Emissive plates"]
	for pass_name: String in ["all_on", "beams_emissive_off"]:
		var toggles: Dictionary = _all_toggles(false)
		if pass_name == "beams_emissive_off":
			for t: String in toggle_names:
				toggles[t] = false
		var still_hidden: bool = true
		for n: Node3D in hidden:
			if Filters.visible_after_toggles(n, toggles):
				still_hidden = false
		_check(still_hidden, "2.5 %s: real SM_DonutShell/SM_Sphere4Count stay hidden" % pass_name, "real hidden fixture revealed (%s)" % pass_name)
	var revealed: int = 0
	for n2: Node3D in hidden:
		if Filters.visible_after_toggles(n2, _all_toggles(true)):
			revealed += 1
	_check(revealed == hidden.size(), "2.6 Hidden in game reveals all %d real fixtures" % hidden.size(), "revealed %d/%d" % [revealed, hidden.size()])
	var stats: Dictionary = Tagger.collect_stats(host)
	_check(int(stats.get("hidden_nodes", 0)) >= 2 and int(stats.get("hidden_records", 0)) >= 2,
		"2.7 collect_stats reports hidden nodes=%d records=%d" % [int(stats.get("hidden_nodes", 0)), int(stats.get("hidden_records", 0))],
		"hidden stats missing: " + str(stats.get("hidden_nodes", -1)))
	host.free()
	ll.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))


func _test_authored_hidden_accounting() -> void:
	var family: int = _count_hidden_flags_in_dirs([
		"res://data/generated/levels/Guildhall",
		"res://data/generated/levels/Buildings/Guildhall",
	])
	if family == 0:
		print("SKIP: Guildhall generated JSONs absent; authored-hidden accounting skipped")
		return
	var resolved: Dictionary = MapData.resolve_sublevels("guildhall")
	var paths: Array = resolved.get("paths", [])
	var resolved_hidden: int = 0
	for p: Variant in paths:
		resolved_hidden += _count_hidden_flags(str(p))
	print("AUTHORED_HIDDEN guildhall_family=", family, " resolved_sublevels=", paths.size(), " resolved_hidden=", resolved_hidden)
	_check(paths.size() >= 15, "3.1 guildhall review resolves the full 15-sublevel base (%d resolved)" % paths.size(), "unexpected sublevel count %d" % paths.size())
	_check(resolved_hidden == 697, "3.2 697 authored bHiddenInGame records in the 15 review sublevels", "resolved hidden=%d (expected 697)" % resolved_hidden)
	_check(family == 710, "3.3 710 authored bHiddenInGame records across the Guildhall level family", "family hidden=%d (expected 710)" % family)
	_check(family - resolved_hidden == 13, "3.4 the 13-record difference is the contract-scoped facade/teleporter files", "difference=%d" % (family - resolved_hidden))


## Headless proxy for "Foyer/Library are not black": review mode used to have
## no WorldEnvironment at all, so the viewport cleared to the default black.
## Pixel captures need a GPU run (see docs/reports/w0t-review-truth.md); this
## asserts the environment review now builds: a real preset, BG_SKY + sky
## material, and a non-zero ambient floor (>= 0.02, matching WeatherProfile's
## clamp) plus a moon (>= 0.1 energy). Threshold rationale: ambient + moon +
## sky are the three sources that lift flat geometry off 0; before W0T there
## was no WorldEnvironment at all, so the viewport cleared black.
func _test_review_environment() -> void:
	var host: Node3D = Node3D.new()
	host.name = "ReviewEnvHost"
	root.add_child(host)
	var report: Dictionary = ReviewEnvironment.build(host, "guildhall", false)
	var we: WorldEnvironment = null
	var moon: DirectionalLight3D = null
	for c: Node in host.get_children():
		if c is WorldEnvironment:
			we = c as WorldEnvironment
		elif c is DirectionalLight3D and str(c.name) == "ReviewMoon":
			moon = c as DirectionalLight3D
	_check(str(report.get("preset", "")) == "midnight_clear", "5.1 guildhall review uses the authored midnight_clear preset (%s)" % str(report.get("preset", "")), "preset=" + str(report.get("preset", "")))
	_check(we != null and we.environment != null, "5.2 review mode builds a WorldEnvironment", "no WorldEnvironment")
	if we != null and we.environment != null:
		var env: Environment = we.environment
		_check(env.background_mode == Environment.BG_SKY and env.sky != null, "5.3 Guildhall review env is BG_SKY with a real sky", "bg=%d sky=%s" % [env.background_mode, str(env.sky != null)])
		_check(env.ambient_light_energy >= 0.02, "5.4 ambient floor >= 0.02 (%.3f)" % env.ambient_light_energy, "ambient_energy=%.4f" % env.ambient_light_energy)
		_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY or env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "5.5 ambient source is sky/color", "ambient_source=%d" % env.ambient_light_source)
		_check(env.sky.sky_material != null and env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
			"5.6 sky material present + reflections from sky", "sky material/reflection source not set")
	_check(moon != null and moon.light_energy >= 0.1, "5.7 review moon present with energy >= 0.1", "moon missing/dim")
	host.free()


func _first_hidden_mesh(json_path: String, stem: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (raw is Dictionary):
		return {}
	for m_v: Variant in ((raw as Dictionary).get("meshes", []) as Array):
		if not (m_v is Dictionary):
			continue
		var m: Dictionary = m_v as Dictionary
		if not bool(m.get("hidden_in_game", false)):
			continue
		var mesh_path: String = str(m.get("mesh", ""))
		if mesh_path.ends_with(stem):
			return m.duplicate(true)
	return {}


func _find_ue(host: Node, stems: Array[String]) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.push_back(c)
		if not (n is Node3D) or not n.has_meta("ue_mesh"):
			continue
		var mp: String = str(n.get_meta("ue_mesh"))
		for stem: String in stems:
			if mp.ends_with(stem):
				out.append(n as Node3D)
				break
	return out


func _count_hidden_flags_in_dirs(dirs: Array[String]) -> int:
	var total: int = 0
	for dir: String in dirs:
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
			continue
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".tatlevel.json"):
				total += _count_hidden_flags(dir.path_join(f))
	return total


func _count_hidden_flags(json_path: String) -> int:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (raw is Dictionary):
		return 0
	var count: int = 0
	var stack: Array = [raw]
	while not stack.is_empty():
		var v: Variant = stack.pop_back()
		if v is Dictionary:
			if bool((v as Dictionary).get("hidden_in_game", false)):
				count += 1
			for child: Variant in (v as Dictionary).values():
				if child is Dictionary or child is Array:
					stack.push_back(child)
		elif v is Array:
			for child2: Variant in (v as Array):
				if child2 is Dictionary or child2 is Array:
					stack.push_back(child2)
	return count
