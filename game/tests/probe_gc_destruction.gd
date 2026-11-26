extends SceneTree
## W10-A3-GC headless destruction probe.
##
## The shipped destructibles are authored hidden GeometryCollection overlays
## (336 components on 264 actors: 93 chest lids, 68 display-case doors, plus
## bookcase/window glass). The port emits them as a separate hidden layer and
## keeps the intact leaf (SM_ChestTrunkALid / SM_DisplayCaseADoor) visible; on
## break the runtime hides the leaf and shows the authored broken overlay.
##
## This probe checks, from the real generated payload and a real Guildhall_Loot
## load:
##   1. payload census: 336 components / 336 authored hidden / 0 visible /
##      0 visible-without-mesh / 336 emitted / 166 intact leaves
##      (93 chests + 68 display-case doors + 5 BP_Manor_Displaycase doors);
##   2. a real load builds 95 hidden broken layers and 79 visible leaves for
##      Guildhall_Loot, all with a mesh and no collision node;
##   2b. owner index: 95 layers = 48 chest + 31 display case + 16 bookcase;
##      87 owners = 79 containers (each with BOTH leaf and broken) + 8
##      BP_Manor_Bookcase_Cabinet_MinorLoot actors (2 glass doors each, no leaf);
##      every authored chest/display-case container record resolves a pair;
##   3. a control load with `TAT2_GC_LAYERS=off` emits the same collision shape
##      and body counts (the layers add no collision);
##   4. one chest and one display case swap intact -> broken on
##      `break_container()`, fire `broken_changed`/`container_broken`, open
##      once (loot behaviour unchanged), and leave every other overlay hidden.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     'tools/godot --headless --path game --script res://tests/probe_gc_destruction.gd'
##
## Prints GC_PROBE PASS/FAIL; exits 1 on failure, 2 when the extracted assets
## are absent (cannot measure the real meshes).

const LEVELS_ROOT := "res://data/generated/levels/"
const GUILDHALL_LOOT := "res://data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json"
const ENV_GC_LAYERS := "TAT2_GC_LAYERS"

const EXPECTED_COMPONENTS := 336
const EXPECTED_HIDDEN := 336
const EXPECTED_VISIBLE_EMITTED := 0
const EXPECTED_EMITTED := 336
const EXPECTED_LEAVES := 166
const EXPECTED_FALLBACK_BROKEN := 93
const EXPECTED_SIBLING_SMC := 5
## LevelInstance merges copy records into the parent payload, so the generated
## tree carries 39 extra placement copies (375 total; SkyboxGeo alone repeats
## one storefront glass 14x) and 2 extra leaf copies (168 total). The authored
## source census stays 336/166 in `gc_stats`.
const EXPECTED_PLACEMENTS := 375
const EXPECTED_PLACEMENT_LEAVES := 168
const EXPECTED_PLACEMENT_SIBLING_SMC := 7
const EXPECTED_GUILDHALL_LOOT_LAYERS := 95
const EXPECTED_GUILDHALL_LOOT_LEAVES := 79

var _fails: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("GC_CHECK PASS ", name, " ", detail)
	else:
		_fails += 1
		printerr("GC_CHECK FAIL ", name, " ", detail)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt: String = FileAccess.get_file_as_string(path)
	if txt == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	return parsed as Dictionary if parsed is Dictionary else {}


func _collect_levels(dir_path: String, out: Array[String]) -> void:
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var name: String = da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var full: String = dir_path.path_join(name)
		if da.current_is_dir():
			_collect_levels(full, out)
		elif name.ends_with(".tatlevel.json"):
			out.append(full)
		name = da.get_next()
	da.list_dir_end()


func _collect_gc_nodes(node: Node, leaves: Array[MeshInstance3D], broken: Array[MeshInstance3D]) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			var role: String = str(mi.get_meta("gc_role", ""))
			if role == "leaf":
				leaves.append(mi)
			elif role == "broken":
				broken.append(mi)
		_collect_gc_nodes(child, leaves, broken)


func _count_collision_children(node: Node) -> int:
	var n: int = 0
	for child: Node in node.get_children():
		if child is CollisionShape3D or child is CollisionObject3D:
			n += 1
		n += _count_collision_children(child)
	return n


func _payload_census() -> Dictionary:
	var files: Array[String] = []
	_collect_levels(LEVELS_ROOT, files)
	var out := {
		"levels": 0,
		"components": 0,
		"hidden": 0,
		"visible": 0,
		"visible_emitted": 0,
		"emitted": 0,
		"visible_missing_mesh": 0,
		"missing_mesh": 0,
		"leaves": 0,
		"fallback_broken": 0,
		"sibling_smc": 0,
		"unresolved": 0,
		"stats_components": 0,
		"stats_hidden": 0,
		"stats_leaves": 0,
		"stats_fallback_broken": 0,
		"stats_sibling_smc": 0,
	}
	for f: String in files:
		var d: Dictionary = _read_json(f)
		if d.is_empty():
			continue
		var has_gc: bool = false
		for g_var: Variant in (d.get("gc", []) as Array):
			if not (g_var is Dictionary):
				continue
			has_gc = true
			var g: Dictionary = g_var as Dictionary
			out["components"] = int(out["components"]) + 1
			var hidden: bool = g.get("hidden") == true
			if hidden:
				out["hidden"] = int(out["hidden"]) + 1
			else:
				out["visible"] = int(out["visible"]) + 1
			var mesh: String = str(g.get("mesh", ""))
			if mesh == "":
				out["missing_mesh"] = int(out["missing_mesh"]) + 1
				if not hidden:
					out["visible_missing_mesh"] = int(out["visible_missing_mesh"]) + 1
			else:
				out["emitted"] = int(out["emitted"]) + 1
				if not hidden:
					out["visible_emitted"] = int(out["visible_emitted"]) + 1
			match str(g.get("source", "")):
				"fallback_broken":
					out["fallback_broken"] = int(out["fallback_broken"]) + 1
				"sibling_smc":
					out["sibling_smc"] = int(out["sibling_smc"]) + 1
		for l_var: Variant in (d.get("gc_leaves", []) as Array):
			if l_var is Dictionary:
				out["leaves"] = int(out["leaves"]) + 1
		var stats: Dictionary = d.get("gc_stats", {}) as Dictionary
		out["stats_components"] = int(out["stats_components"]) + int(stats.get("components", 0))
		out["stats_hidden"] = int(out["stats_hidden"]) + int(stats.get("hidden", 0))
		out["stats_leaves"] = int(out["stats_leaves"]) + int(stats.get("leaves", 0))
		out["stats_fallback_broken"] = int(out["stats_fallback_broken"]) + int(stats.get("fallback_broken", 0))
		out["stats_sibling_smc"] = int(out["stats_sibling_smc"]) + int(stats.get("sibling_smc", 0))
		out["unresolved"] = int(out["unresolved"]) + int(stats.get("unresolved", 0))
		if has_gc:
			out["levels"] = int(out["levels"]) + 1
	return out


func _make_loader() -> Node:
	var scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	if scr == null:
		return null
	var ll: Node = scr.new() as Node
	root.add_child(ll)
	return ll


func _build_containers(loader: Node, loot_records: Array, host: Node3D, pair_failures: Array) -> Array:
	var out: Array = []
	var ContainerScript: GDScript = load("res://src/interact/loot_container.gd") as GDScript
	for i in range(loot_records.size()):
		var e_var: Variant = loot_records[i]
		if not (e_var is Dictionary):
			continue
		var e: Dictionary = e_var as Dictionary
		var cls: String = str(e.get("class", ""))
		# Only the two destructible families this probe exercises. Stash and
		# storefront containers author no GC and are not expected to pair.
		if cls.find("ChestTrunk") < 0 and cls.find("DisplayCaseA") < 0:
			continue
		var owner: String = str(e.get("owner", ""))
		var c: Node = ContainerScript.new() as Node
		c.call("configure", cls, e, i)
		host.add_child(c)
		var gcv: Dictionary = loader.call("gc_visuals_for", owner) as Dictionary
		var leaf: Node3D = gcv.get("leaf") as Node3D
		var broken: Node3D = gcv.get("broken") as Node3D
		if leaf == null or not is_instance_valid(leaf) or broken == null or not is_instance_valid(broken):
			pair_failures.append("%s(%s)" % [owner, cls])
		else:
			c.call("bind_gc_visuals", leaf, broken)
		out.append(c)
	return out


func _first_of(containers: Array, token: String) -> Node:
	for c: Node in containers:
		if str(c.get("container_class")).find(token) >= 0:
			return c
	return null


func _run() -> void:
	await process_frame
	if DirAccess.open("res://assets/ue/Content") == null:
		printerr("GC_PROBE SKIP assets/ue/Content missing (extracted/ not present)")
		quit(2)
		return

	# --- 1. Payload census (all generated levels) ---------------------------
	var census: Dictionary = _payload_census()
	print("GC_PROBE payload authored_components=%d authored_hidden=%d placements=%d placement_hidden=%d visible=%d emitted=%d placement_leaves=%d authored_leaves=%d fallback_broken=%d sibling_smc=%d unresolved=%d" % [
		int(census["stats_components"]), int(census["stats_hidden"]),
		int(census["components"]), int(census["hidden"]), int(census["visible"]),
		int(census["emitted"]), int(census["leaves"]), int(census["stats_leaves"]),
		int(census["stats_fallback_broken"]), int(census["stats_sibling_smc"]),
		int(census["unresolved"])])
	_check(int(census["stats_components"]) == EXPECTED_COMPONENTS, "authored GC components",
		"%d (expected %d)" % [int(census["stats_components"]), EXPECTED_COMPONENTS])
	_check(int(census["stats_hidden"]) == EXPECTED_HIDDEN, "authored GC hidden",
		"%d/%d (expected %d/%d)" % [int(census["stats_hidden"]), int(census["stats_components"]), EXPECTED_HIDDEN, EXPECTED_COMPONENTS])
	_check(int(census["components"]) == EXPECTED_PLACEMENTS and int(census["hidden"]) == int(census["components"]),
		"placement records (LevelInstance copies included)",
		"components=%d hidden=%d (expected %d/%d)" % [int(census["components"]), int(census["hidden"]), EXPECTED_PLACEMENTS, EXPECTED_PLACEMENTS])
	_check(int(census["components"]) == int(census["stats_components"]) + 39, "LevelInstance GC placements accounted",
		"%d authored + 39 merged copies = %d" % [int(census["stats_components"]), int(census["components"])])
	_check(int(census["visible_missing_mesh"]) == 0, "visible GC without a mesh (fail-loud class)",
		"%d" % int(census["visible_missing_mesh"]))
	_check(int(census["missing_mesh"]) == 0, "any GC without a mesh",
		"missing=%d" % int(census["missing_mesh"]))
	_check(int(census["emitted"]) == int(census["components"]), "broken layers emitted",
		"%d/%d" % [int(census["emitted"]), int(census["components"])])
	_check(int(census["visible_emitted"]) == EXPECTED_VISIBLE_EMITTED, "authored-visible GC emitted",
		"%d (expected %d today)" % [int(census["visible_emitted"]), EXPECTED_VISIBLE_EMITTED])
	_check(int(census["stats_leaves"]) == EXPECTED_LEAVES, "authored intact leaf records",
		"%d (expected %d)" % [int(census["stats_leaves"]), EXPECTED_LEAVES])
	_check(int(census["leaves"]) == EXPECTED_PLACEMENT_LEAVES, "intact leaf placements",
		"%d (expected %d = 166 authored + 2 copies)" % [int(census["leaves"]), EXPECTED_PLACEMENT_LEAVES])
	_check(int(census["stats_fallback_broken"]) == EXPECTED_FALLBACK_BROKEN, "GC_ChestTrunkALid labelled fallback",
		"%d (expected %d, no dump)" % [int(census["stats_fallback_broken"]), EXPECTED_FALLBACK_BROKEN])
	_check(int(census["stats_sibling_smc"]) == EXPECTED_SIBLING_SMC, "bookcase GC sibling-SMC fallback",
		"%d (expected %d, no AutoInstanceMeshes mesh)" % [int(census["stats_sibling_smc"]), EXPECTED_SIBLING_SMC])
	_check(int(census["unresolved"]) == 0, "unresolved GC records", "%d" % int(census["unresolved"]))

	# --- 2. Real Guildhall_Loot load, GC layers on --------------------------
	OS.set_environment(ENV_GC_LAYERS, "on")
	var loader: Node = _make_loader()
	if loader == null:
		_check(false, "level_loader.gd loads", "")
		_finish()
		return
	var host := Node3D.new()
	host.name = "GCHost"
	root.add_child(host)
	var paths: Array[String] = [GUILDHALL_LOOT]
	var res: Dictionary = loader.call("load_sublevels", paths, host, null, 8, true) as Dictionary
	var leaves: Array[MeshInstance3D] = []
	var broken: Array[MeshInstance3D] = []
	_collect_gc_nodes(host, leaves, broken)
	var hidden_initial: int = 0
	var meshless: int = 0
	var colliding: int = 0
	for b: MeshInstance3D in broken:
		if not b.visible:
			hidden_initial += 1
		if b.mesh == null:
			meshless += 1
		if _count_collision_children(b) > 0:
			colliding += 1
	for l: MeshInstance3D in leaves:
		if _count_collision_children(l) > 0:
			colliding += 1
	print("GC_PROBE load layers=%d leaves=%d hidden_initial=%d visible_broken=%d meshless=%d owner_index=%d collision_shapes=%d" % [
		broken.size(), leaves.size(), hidden_initial, int(res.get("gc_visible_broken", -1)),
		meshless, int(res.get("gc_owner_count", -1)), int(res.get("collision_shapes", -1))])
	_check(broken.size() == EXPECTED_GUILDHALL_LOOT_LAYERS, "Guildhall_Loot broken layers",
		"%d (expected %d)" % [broken.size(), EXPECTED_GUILDHALL_LOOT_LAYERS])
	_check(leaves.size() == EXPECTED_GUILDHALL_LOOT_LEAVES, "Guildhall_Loot intact leaves",
		"%d (expected %d)" % [leaves.size(), EXPECTED_GUILDHALL_LOOT_LEAVES])
	_check(hidden_initial == broken.size(), "every broken layer hidden initially",
		"%d/%d hidden" % [hidden_initial, broken.size()])
	_check(int(res.get("gc_visible_broken", -1)) == 0, "loader reports 0 visible broken layers",
		"%d" % int(res.get("gc_visible_broken", -1)))
	_check(meshless == 0 and int(res.get("gc_missing_mesh", -1)) == 0, "broken layer meshes resolved",
		"meshless=%d loader_missing=%d" % [meshless, int(res.get("gc_missing_mesh", -1))])
	_check(colliding == 0, "GC layer nodes own no collision",
		"colliding_nodes=%d" % colliding)
	var leaves_visible: int = 0
	for l2: MeshInstance3D in leaves:
		if l2.visible:
			leaves_visible += 1
	_check(leaves_visible == leaves.size(), "intact leaves visible before break",
		"%d/%d visible" % [leaves_visible, leaves.size()])

	# --- 2b. Owner index: which layers have no leaf, and does every authored
	# chest/display-case container receive BOTH a leaf and a broken layer? -----
	var broken_kinds: Dictionary = {}
	var leaf_kinds: Dictionary = {}
	var owners_broken: Dictionary = {}
	var owners_leaf: Dictionary = {}
	var broken_per_owner: Dictionary = {}
	var broken_only_non_bookcase: Array[String] = []
	for b3: MeshInstance3D in broken:
		var bk: String = str(b3.get_meta("gc_kind", "other"))
		broken_kinds[bk] = int(broken_kinds.get(bk, 0)) + 1
		var bo: String = str(b3.get_meta("gc_owner", ""))
		owners_broken[bo] = true
		broken_per_owner[bo] = int(broken_per_owner.get(bo, 0)) + 1
	for l4: MeshInstance3D in leaves:
		var lk: String = str(l4.get_meta("gc_kind", "other"))
		leaf_kinds[lk] = int(leaf_kinds.get(lk, 0)) + 1
		owners_leaf[str(l4.get_meta("gc_owner", ""))] = true
	var paired_owners: int = 0
	var broken_only_owners: Array[String] = []
	for o: String in owners_broken.keys():
		if owners_leaf.has(o):
			paired_owners += 1
		else:
			broken_only_owners.append(o)
			var kc: String = ""
			for b4: MeshInstance3D in broken:
				if str(b4.get_meta("gc_owner", "")) == o:
					kc = str(b4.get_meta("gc_kind", ""))
					break
			if kc != "bookcase" or int(broken_per_owner.get(o, 0)) != 2:
				broken_only_non_bookcase.append("%s(%s x%d)" % [o, kc, int(broken_per_owner.get(o, 0))])
	print("GC_PROBE owner_index broken_owners=%d leaf_owners=%d paired=%d broken_only=%d broken_kinds=%s leaf_kinds=%s" % [
		owners_broken.size(), owners_leaf.size(), paired_owners, broken_only_owners.size(), str(broken_kinds), str(leaf_kinds)])
	_check(int(broken_kinds.get("chest", 0)) == 48 and int(broken_kinds.get("display_case", 0)) == 31,
		"broken layers are 48 chest + 31 display-case",
		"chest=%d display_case=%d" % [int(broken_kinds.get("chest", 0)), int(broken_kinds.get("display_case", 0))])
	_check(int(broken_kinds.get("bookcase", 0)) == 16, "16 bookcase broken layers",
		"%d on %d actors (2 doors each)" % [int(broken_kinds.get("bookcase", 0)), broken_only_owners.size()])
	_check(int(leaf_kinds.get("chest", 0)) == 48 and int(leaf_kinds.get("display_case", 0)) == 31,
		"intact leaves are 48 chest + 31 display-case",
		"chest=%d display_case=%d" % [int(leaf_kinds.get("chest", 0)), int(leaf_kinds.get("display_case", 0))])
	_check(owners_leaf.size() == 79 and paired_owners == 79, "79 owners have both leaf and broken",
		"leaf_owners=%d paired=%d" % [owners_leaf.size(), paired_owners])
	_check(broken_only_owners.size() == 8 and broken_only_non_bookcase.is_empty(),
		"8 broken-only owners are bookcase actors with 2 layers each",
		"broken_only=%d unexpected=%s" % [broken_only_owners.size(), str(broken_only_non_bookcase)])
	_check(int(res.get("gc_owner_count", -1)) == 87,
		"owner index 87 == 79 paired containers + 8 bookcases",
		"%d" % int(res.get("gc_owner_count", -1)))

	# --- 3. Control load with the layers disabled: collision unchanged ------
	OS.set_environment(ENV_GC_LAYERS, "off")
	var loader_off: Node = _make_loader()
	var host_off := Node3D.new()
	host_off.name = "GCHostOff"
	root.add_child(host_off)
	var res_off: Dictionary = loader_off.call("load_sublevels", paths, host_off, null, 8, true) as Dictionary
	OS.set_environment(ENV_GC_LAYERS, "on")
	var same_shapes: bool = int(res.get("collision_shapes", -1)) == int(res_off.get("collision_shapes", -2))
	var same_bodies: bool = int(res.get("collision_bodies", -1)) == int(res_off.get("collision_bodies", -2))
	print("GC_PROBE control shapes_on=%d shapes_off=%d bodies_on=%d bodies_off=%d layers_off=%d" % [
		int(res.get("collision_shapes", -1)), int(res_off.get("collision_shapes", -1)),
		int(res.get("collision_bodies", -1)), int(res_off.get("collision_bodies", -1)),
		int(res_off.get("gc_layers_built", -1))])
	_check(same_shapes and same_bodies, "GC layers add no collision (control load)",
		"shapes %d==%d bodies %d==%d" % [
			int(res.get("collision_shapes", -1)), int(res_off.get("collision_shapes", -1)),
			int(res.get("collision_bodies", -1)), int(res_off.get("collision_bodies", -1))])
	_check(int(res_off.get("gc_layers_built", -1)) == 0 and int(res_off.get("gc_leaves_built", -1)) == 0,
		"TAT2_GC_LAYERS=off disables the layers",
		"layers=%d leaves=%d" % [int(res_off.get("gc_layers_built", -1)), int(res_off.get("gc_leaves_built", -1))])

	# --- 4. Break one chest and one display case ----------------------------
	var pair_failures: Array = []
	var containers: Array = _build_containers(loader, res.get("loot_containers", []) as Array, host, pair_failures)
	var destructible_records: int = 0
	for lr_var: Variant in (res.get("loot_containers", []) as Array):
		if lr_var is Dictionary:
			var lr: Dictionary = lr_var as Dictionary
			var lrc: String = str(lr.get("class", ""))
			if lrc.find("ChestTrunk") >= 0 or lrc.find("DisplayCaseA") >= 0:
				destructible_records += 1
	_check(destructible_records == 79 and containers.size() == 79 and pair_failures.is_empty(),
		"every authored chest/display-case container has a bound pair",
		"records=%d built=%d failures=%s" % [destructible_records, containers.size(), str(pair_failures)])
	var chest: Node = _first_of(containers, "ChestTrunk")
	var case: Node = _first_of(containers, "DisplayCaseA")
	_check(chest != null, "chest container found", "class=BP_ChestTrunk_MajorLoot_C")
	_check(case != null, "display-case container found", "class=BP_DisplayCaseA_MajorLoot_C")
	var chest_leaf: Node3D = null
	var chest_broken: Node3D = null
	var case_leaf: Node3D = null
	var case_broken: Node3D = null
	if chest != null:
		var cgv: Dictionary = loader.call("gc_visuals_for", str(chest.get("owner_name"))) as Dictionary
		chest_leaf = cgv.get("leaf") as Node3D
		chest_broken = cgv.get("broken") as Node3D
	if case != null:
		var cgv2: Dictionary = loader.call("gc_visuals_for", str(case.get("owner_name"))) as Dictionary
		case_leaf = cgv2.get("leaf") as Node3D
		case_broken = cgv2.get("broken") as Node3D
	_check(chest_leaf != null and chest_broken != null, "chest bindings resolved",
		"leaf=%s broken=%s" % [str(chest_leaf != null), str(chest_broken != null)])
	_check(case_leaf != null and case_broken != null, "display-case bindings resolved",
		"leaf=%s broken=%s" % [str(case_leaf != null), str(case_broken != null)])

	var chest_signals: Dictionary = {"n": 0}
	var case_signals: Dictionary = {"n": 0}
	if chest != null:
		chest.connect("broken_changed", func(_b: bool) -> void: chest_signals["n"] = int(chest_signals["n"]) + 1)
		chest.connect("container_broken", func(_c: Node, _a: Node) -> void: chest_signals["n"] = int(chest_signals["n"]) + 10)
	if case != null:
		case.connect("broken_changed", func(_b: bool) -> void: case_signals["n"] = int(case_signals["n"]) + 1)
		case.connect("container_broken", func(_c: Node, _a: Node) -> void: case_signals["n"] = int(case_signals["n"]) + 10)

	if chest != null and chest_leaf != null and chest_broken != null:
		_check(chest_leaf.visible and not chest_broken.visible, "chest intact before break",
			"leaf=%s broken=%s" % [str(chest_leaf.visible), str(chest_broken.visible)])
		var broke: bool = bool(chest.call("break_container", null))
		var broke_again: bool = bool(chest.call("break_container", null))
		_check(broke and not broke_again, "chest break is one-shot",
			"first=%s second=%s" % [str(broke), str(broke_again)])
		_check((not chest_leaf.visible) and chest_broken.visible, "chest intact -> broken swap",
			"leaf=%s broken=%s" % [str(chest_leaf.visible), str(chest_broken.visible)])
		_check(bool(chest.call("is_broken")) and chest.get_meta("broken", false) == true,
			"chest broken state recorded", "is_broken + meta")
		_check(int(chest_signals["n"]) == 11, "chest break signals",
			"broken_changed(1)+container_broken(10)=%d" % int(chest_signals["n"]))
		# `_open_container()` is the same one-shot loot gate as a normal interact.
		var opened_flag: bool = bool(chest.get("opened")) or chest.get_meta("opened", false) == true
		_check(opened_flag, "chest break opened the container once (loot behaviour kept)",
			"opened=%s" % str(chest.get("opened")))

	if case != null and case_leaf != null and case_broken != null:
		_check(case_leaf.visible and not case_broken.visible, "display case intact before break",
			"leaf=%s broken=%s" % [str(case_leaf.visible), str(case_broken.visible)])
		var broke2: bool = bool(case.call("break_container", null))
		_check(broke2 and (not case_leaf.visible) and case_broken.visible,
			"display case intact -> broken swap",
			"leaf=%s broken=%s" % [str(case_leaf.visible), str(case_broken.visible)])
		_check(int(case_signals["n"]) == 11, "display-case break signals",
			"broken_changed(1)+container_broken(10)=%d" % int(case_signals["n"]))

	# Exactly the two broken overlays are visible; every other layer stays off.
	var visible_after: int = 0
	for b2: MeshInstance3D in broken:
		if b2.visible:
			visible_after += 1
	print("GC_PROBE after_break visible_broken=%d of %d" % [visible_after, broken.size()])
	_check(visible_after == 2, "only the two broken overlays are visible",
		"%d/%d" % [visible_after, broken.size()])
	var leaves_after: int = 0
	for l3: MeshInstance3D in leaves:
		if l3.visible:
			leaves_after += 1
	_check(leaves_after == leaves.size() - 2, "only the two intact leaves were hidden",
		"%d/%d visible" % [leaves_after, leaves.size()])

	_finish()


func _finish() -> void:
	print("GC_PROBE checks=%d fails=%d" % [_checks, _fails])
	print("GC_PROBE ", "PASS" if _fails == 0 else "FAIL")
	quit(0 if _fails == 0 else 1)
