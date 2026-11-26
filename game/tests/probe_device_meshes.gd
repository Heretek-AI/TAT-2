extends SceneTree
## W10-A3 turret/device mesh emission gate (headless).
##
## The producer used to read the raw level SMC stub for `StaticMesh` and the raw
## transform, so every BP-only component (turret parts, beam hardware, ward
## quads, vault doors, ...) was either dropped or placed at its owner origin.
## The fix resolves the merged SCS/archetype props and the merged transform.
##
## This probe pins the measured Guildhall_Gameplay result:
##
##   TURRET_ACTORS   229  BP_SecurityTurret* actors
##   TURRET_PARTS    1145 visible turret parts
##   TURRET_BASEWALL 66 visible / 163 hidden
##   TURRET_ALL      1308 authored parts (1145 visible + 163 hidden BaseWall)
##
## 1,308 is the trap: six component entries per actor (1,374) minus the 66
## wall-mounted variants whose CameraBase1 is explicitly `bVisible: false`
## equals 1,308, but that count still includes the 163 BaseWall plates whose
## template default is `bVisible: false` and whose level stub does not override
## it. The gate is 1,145 visible parts, not 1,308 total parts.
##
## Every visible turret part must also carry the producer's `no_collide: true`
## (the loader keeps its 31,400 building / 32,000 total shape budget for
## masonry; the collision probe measures the shape count), resolve to an
## existing GLB, and no /Game/Developers/ debug mesh may be visible anywhere in
## the level. The loader phase at the end proves the flag survives batching and
## keeps every turret path out of the collision-path census.
##
## Run:
##   tools/godot --headless --path game --script res://tests/probe_device_meshes.gd
##
## Prints `TURRET_PROBE PASS|FAIL` and exits non-zero on failure.

const LEVEL_PATH := "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"
const EXPECTED_TURRET_ACTORS := 229
const EXPECTED_VISIBLE_TURRET_PARTS := 1145
const EXPECTED_VISIBLE_BASEWALL := 66
const EXPECTED_HIDDEN_BASEWALL := 163
const TURRET_CLASS_PREFIX := "BP_SecurityTurret"
const TURRET_MESH_PREFIX := "/game/art/gameplay/turrets/"
const BASEWALL_MESH := "/game/art/gameplay/turrets/boltturret/sm_turretbasewall"
const DEV_MESH_PREFIX := "/game/developers/"

var _fails: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String, detail: String) -> void:
	_checks += 1
	if ok:
		print("  ok: ", name, " ", detail)
	else:
		_fails += 1
		printerr("  FAIL: ", name, " ", detail)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt: String = FileAccess.get_file_as_string(path)
	if txt == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	return parsed as Dictionary if parsed is Dictionary else {}


## Mirror of level_loader._ue_mesh_to_res() for the authored turret folder.
func _glb_exists(ue_mesh: String) -> bool:
	var clean: String = ue_mesh.split(".")[0]
	if clean.begins_with("/Game/"):
		clean = clean.substr(6)
	return ResourceLoader.exists("res://assets/ue/Content/" + clean + ".glb")


func _run() -> void:
	var d: Dictionary = _read_json(LEVEL_PATH)
	if d.is_empty():
		printerr("TURRET_PROBE FAIL reason=missing_level path=", LEVEL_PATH)
		quit(1)
		return

	var turret_actors: int = 0
	for a_var: Variant in (d.get("actors", []) as Array):
		if not (a_var is Dictionary):
			continue
		var cls: String = str((a_var as Dictionary).get("class", ""))
		if cls.begins_with(TURRET_CLASS_PREFIX):
			turret_actors += 1

	var visible_parts: int = 0
	var hidden_parts: int = 0
	var visible_basewall: int = 0
	var hidden_basewall: int = 0
	var hidden_basewall_emitted: int = 0
	var visible_flagged: int = 0
	var missing_glbs: int = 0
	var missing_samples: Array[String] = []
	var dev_total: int = 0
	var dev_visible: int = 0
	var dev_samples: Array[String] = []
	var visible_meshes: Dictionary = {}

	for m_var: Variant in (d.get("meshes", []) as Array):
		if not (m_var is Dictionary):
			continue
		var m: Dictionary = m_var as Dictionary
		var mp: String = str(m.get("mesh", ""))
		var low: String = mp.to_lower()
		var hidden: bool = m.get("hidden_in_game", false) is bool and bool(m.get("hidden_in_game", false))
		if low.find(DEV_MESH_PREFIX) >= 0:
			dev_total += 1
			if not hidden:
				dev_visible += 1
				if dev_samples.size() < 4 and not dev_samples.has(mp):
					dev_samples.append(mp)
			continue
		if not low.begins_with(TURRET_MESH_PREFIX):
			continue
		if hidden:
			hidden_parts += 1
			if low.begins_with(BASEWALL_MESH):
				hidden_basewall_emitted += 1
			continue
		visible_parts += 1
		visible_meshes[mp] = int(visible_meshes.get(mp, 0)) + 1
		if low.begins_with(BASEWALL_MESH):
			visible_basewall += 1
		if bool(m.get("no_collide", false)):
			visible_flagged += 1
		if not _glb_exists(mp):
			missing_glbs += 1
			if missing_samples.size() < 4 and not missing_samples.has(mp):
				missing_samples.append(mp)

	var all_parts: int = visible_parts + hidden_parts
	# The authored census: every BP_SecurityTurret* actor owns exactly one
	# SM_TurretBaseWall stub. 66 level stubs override the template's
	# `bVisible: false`; the other 163 stay invisible and the producer never
	# emits them (invisible, no collision, no draw call).
	hidden_basewall = maxi(turret_actors - visible_basewall, 0)
	var authored_parts: int = visible_parts + hidden_basewall

	print("TURRET_ACTORS count=", turret_actors, " expected=", EXPECTED_TURRET_ACTORS)
	_check(turret_actors == EXPECTED_TURRET_ACTORS, "turret actors",
		"count=%d" % turret_actors)

	print("TURRET_PARTS visible=", visible_parts, " expected=", EXPECTED_VISIBLE_TURRET_PARTS)
	_check(visible_parts == EXPECTED_VISIBLE_TURRET_PARTS, "visible turret parts",
		"visible=%d expected=%d" % [visible_parts, EXPECTED_VISIBLE_TURRET_PARTS])

	print("TURRET_BASEWALL visible=", visible_basewall, " hidden=", hidden_basewall,
		" emitted_hidden=", hidden_basewall_emitted,
		" expected=%d/%d" % [EXPECTED_VISIBLE_BASEWALL, EXPECTED_HIDDEN_BASEWALL])
	_check(
		visible_basewall == EXPECTED_VISIBLE_BASEWALL
		and hidden_basewall == EXPECTED_HIDDEN_BASEWALL
		and hidden_basewall_emitted == 0,
		"BaseWall visible/hidden split",
		"%d/%d emitted_hidden=%d" % [visible_basewall, hidden_basewall, hidden_basewall_emitted]
	)

	print("TURRET_ALL authored=", authored_parts, " emitted=", all_parts,
		" visible=", visible_parts, " hidden_basewall=", hidden_basewall,
		" (the %d authored count includes %d invisible BaseWall plates; the gate is %d visible)" % [
			authored_parts, hidden_basewall, EXPECTED_VISIBLE_TURRET_PARTS
		])
	_check(authored_parts == 1308, "authored census is 1,308 including hidden BaseWall",
		"authored=%d" % authored_parts)
	_check(all_parts == visible_parts, "no hidden turret part is emitted",
		"emitted=%d visible=%d" % [all_parts, visible_parts])

	print("TURRET_NOCOLLIDE flagged=", visible_flagged, "/", visible_parts)
	_check(visible_flagged == visible_parts, "turret parts opt out of building collision",
		"flagged=%d visible=%d" % [visible_flagged, visible_parts])

	print("TURRET_GLB missing=", missing_glbs, " checked=", visible_parts,
		("" if missing_samples.is_empty() else " samples=" + ",".join(missing_samples)))
	_check(missing_glbs == 0, "every visible turret part resolves a GLB",
		"missing=%d" % missing_glbs)

	print("TURRET_DEVELOPER visible=", dev_visible, " total=", dev_total,
		("" if dev_samples.is_empty() else " samples=" + ",".join(dev_samples)))
	_check(dev_visible == 0, "no visible /Game/Developers/ mesh",
		"visible=%d total=%d" % [dev_visible, dev_total])

	print("TURRET_MESHES ", JSON.stringify(visible_meshes))

	# Loader contract: the per-entry flag must survive batching and keep every
	# turret path out of the collidable-path census. A producer-only check would
	# still pass if the loader stopped honouring `no_collide`.
	var host: Node3D = Node3D.new()
	root.add_child(host)
	var ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ll)
	await process_frame
	var acc: Dictionary = ll.call("_new_accumulator") as Dictionary
	ll.call("_parse_sublevel_file", LEVEL_PATH, acc, host)
	var items: Array = ll.call("_collect_draw_items", acc) as Array
	var ctx: Dictionary = ll.call("_new_build_ctx", host, null, true) as Dictionary
	ll.call("_fill_col_path_counts", items, ctx)
	var census: Dictionary = ctx.get("col_path_counts", {}) as Dictionary
	var turret_in_census: int = 0
	for mp_var: Variant in census.keys():
		if str(mp_var).to_lower().begins_with(TURRET_MESH_PREFIX):
			turret_in_census += 1
	var nocollide_items: int = 0
	var nocollide_instances: int = 0
	var nocollide_collidable: int = 0
	for it_var: Variant in items:
		if not (it_var is Dictionary):
			continue
		var it: Dictionary = it_var as Dictionary
		if not bool(it.get("no_collide", false)):
			continue
		if not str(it.get("mp", "")).to_lower().begins_with(TURRET_MESH_PREFIX):
			continue
		nocollide_items += 1
		var it_trs: Array = it.get("trs", []) as Array
		nocollide_instances += it_trs.size()
		if bool(it.get("collide", false)):
			nocollide_collidable += 1
	print("TURRET_LOADER no_collide_batches=", nocollide_items,
		" instances=", nocollide_instances,
		" collidable_flag_still_set=", nocollide_collidable,
		" turret_paths_in_collision_census=", turret_in_census)
	_check(nocollide_instances == visible_parts, "loader batches every turret instance with no_collide",
		"instances=%d visible=%d batches=%d" % [nocollide_instances, visible_parts, nocollide_items])
	_check(nocollide_collidable == nocollide_items,
		"the no_collide flag (not the sublevel collide flag) is what skips collision",
		"collidable=%d/%d" % [nocollide_collidable, nocollide_items])
	_check(turret_in_census == 0, "turret paths are absent from the collision-path census",
		"paths=%d" % turret_in_census)
	host.queue_free()
	ll.queue_free()

	if _fails == 0:
		print("TURRET_PROBE PASS checks=%d actors=%d visible_parts=%d hidden_parts=%d" % [
			_checks, turret_actors, visible_parts, hidden_parts
		])
		quit(0)
	else:
		printerr("TURRET_PROBE FAIL checks=%d fails=%d" % [_checks, _fails])
		quit(1)
