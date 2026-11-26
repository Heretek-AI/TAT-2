extends SceneTree
## W10-A2 civilian regression suite (plan §2.2).
## Run: tools/godot --headless --path game --script res://tests/test_w10a2_civilian.gd
##
## Covers the three measured civilian defects and their controls:
##   1. LOS: the authored POV backward offset (1.2 m) moved the occlusion ray
##      behind the body, so a wall 0.6 m BEHIND a civilian blinded it to a player
##      4 m in FRONT. RED before the head_position() ray fix.
##   2. Facing: the body/head GLBs face +Z while the actor forward is -Z, so
##      MeshRoot needs a 180 deg yaw (skeleton basis.z must follow actor forward).
##   3. Materials: the body GLB and the head GLB carry DIFFERENT authored slot
##      lists (body 3, female head 6, male head 7); one bind of MeshRoot leaves
##      the head on the glTF default white. Specific albedo paths are asserted;
##      the pants albedo is deliberately NOT asserted (producer misclassifies
##      BaseColorOpacity -> opacity, so PantsC binds a male top texture).
##
## Standalone SceneTree test: it is not registered in run_tests.gd (the
## acceptance lane registers suite 117 there). Exits non-zero on any failure.

const SightModel := preload("res://src/ai/sight_model.gd")
const LevelLoaderScript := preload("res://src/core/level_loader.gd")

## Loaded at run time, not preloaded: `--script` compiles the main loop before
## the autoload globals are registered, and civilian_npc.gd references the
## NoiseBus autoload, so a compile-time preload fails with
## "Identifier not found: NoiseBus".
var _civ_script: GDScript = null

## The female rig the albedo assertions are authored against:
## spawners.json BP_CivilianGeneratorFemale_LowerClass1_C.
const FEMALE_BODY := "res://assets/ue/Content/Art/Animation/CivFemale/Skin/Common/SK_CivFemale_Common_01C.glb"
const FEMALE_HEAD := "res://assets/ue/Content/Art/Animation/CivFemale/Skin/Heads/SK_CivFemale_Head_Abby_Short01.glb"
const SHIRT_ALBEDO_SUFFIX := "T_CivFemale_Common_01_Shirt_D.png"
const HEAD_ALBEDO_SUFFIX := "T_CivFemale_Base_Head_D.png"

## Authored counts pinned by mesh_materials.json:
##   /Game/Art/Animation/CivFemale/Skin/Common/SK_CivFemale_Common_01C      -> 3
##   /Game/Art/Animation/CivFemale/Skin/Heads/SK_CivFemale_Head_Abby_Short01 -> 6
const BODY_SLOTS: int = 3
const HEAD_SLOTS: int = 6

var fails: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _summary() -> void:
	print("W10A2_CIV_SUMMARY: fails=", fails, " passed=", checks - fails, " total=", checks)
	quit(1 if fails > 0 else 0)


func _run() -> void:
	await process_frame
	_civ_script = load("res://src/ai/civilian_npc.gd") as GDScript
	if _civ_script == null:
		printerr("FAIL: civilian_npc.gd did not load as a GDScript")
		fails += 1
		_summary()
		return
	# Fail loudly and early when the real assets are not importable: a silent
	# skip here would let the visual regression through the gate.
	if not ResourceLoader.exists(FEMALE_BODY) or not ResourceLoader.exists(FEMALE_HEAD):
		printerr("FAIL: civilian GLBs missing (body=", ResourceLoader.exists(FEMALE_BODY),
			" head=", ResourceLoader.exists(FEMALE_HEAD), "); run --import first")
		fails += 1
		_summary()
		return

	var gd: Node = root.get_node_or_null("GameData")
	if gd == null or not gd.has_method("get_civilian_meshes"):
		printerr("FAIL: GameData autoload with get_civilian_meshes() is missing")
		fails += 1
		_summary()
		return
	var meshes: Array = gd.call("get_civilian_meshes") as Array
	if meshes.is_empty():
		printerr("FAIL: GameData.get_civilian_meshes() is empty")
		fails += 1
		_summary()
		return
	var first: Dictionary = meshes[0] as Dictionary
	var body0: String = str(first.get("body", ""))
	var head0: String = str(first.get("head", ""))
	print("W10A2_CIV: civilian_meshes[0] body=", body0, " head=", head0)
	for rec_v: Variant in meshes:
		var rec: Dictionary = rec_v as Dictionary
		var b: String = str(rec.get("body", ""))
		var h: String = str(rec.get("head", ""))
		if b != "" and not ResourceLoader.exists(b):
			printerr("FAIL: civilian body GLB missing: ", b)
			fails += 1
		if h != "" and not ResourceLoader.exists(h):
			printerr("FAIL: civilian head GLB missing: ", h)
			fails += 1
	if fails > 0:
		_summary()
		return

	# A live LevelLoader is what bind_prop_scene_materials() resolves through
	# its "level_loader" group; without one every surface stays glTF white.
	var ll: Node = LevelLoaderScript.new()
	ll.name = "W10A2LevelLoader"
	root.add_child(ll)
	await process_frame
	var db: Variant = ll.get("_mesh_mats_db")
	var db_slots: int = (db as Dictionary).size() if db is Dictionary else -1
	_check(db_slots > 0, "LevelLoader live with mesh_materials DB (%d meshes)" % db_slots,
		"LevelLoader has no mesh_materials DB (slots=%d)" % db_slots)

	var world := Node3D.new()
	world.name = "W10A2World"
	root.add_child(world)
	_add_floor(world, 400.0)
	await physics_frame

	# --- Case A: wall 0.6 m BEHIND, player 4 m in FRONT ---------------------
	# The wall is added BEFORE the civilian so it exists before the first
	# 0.25 s sight scan; the civilian is frozen idle so it cannot wander.
	var base_a := Vector3.ZERO
	_add_wall(world, base_a + Vector3(0.0, 2.0, 0.6))
	var civ_a := _make_civilian(world, body0, head0, base_a)
	civ_a.set("_idle_ttl", 999.0)
	var player_a := _make_player(world, base_a + Vector3(0.0, 0.0, -4.0))
	await physics_frame
	await physics_frame

	# Precondition: the head-to-player ray really is clear, so a true result is
	# not an accident of range/angle. The head is spelled out here (not via the
	# new SightModel.head_position helper) so this file also runs against the
	# pre-fix code and produces a genuine RED.
	var head_pre_a: Vector3 = civ_a.global_position + Vector3.UP * SightModel.EYE_HEIGHT_M
	var clear_a: bool = _ray(world, head_pre_a, SightModel.target_point(player_a)).is_empty()
	_check(clear_a, "A precondition: head->player ray is clear with the wall behind",
		"A precondition: head->player ray hits something behind the civilian")
	var can_see_a: bool = bool(civ_a.call("_can_see", player_a))
	_check(can_see_a, "A wall 0.6 m behind does not blind the civilian (_can_see true)",
		"A wall 0.6 m behind blinds the civilian (_can_see false)")
	var fled: bool = false
	for _i: int in range(60):
		await physics_frame
		if str(civ_a.call("state_name")) == "flee":
			fled = true
			break
	var yelps_a: int = int(civ_a.get("yelps"))
	_check(fled and yelps_a >= 1, "A civilian flees/yelps at a player 4 m in front (state=flee yelps=%d)" % yelps_a,
		"A civilian did not flee/yelp (state=%s yelps=%d)" % [str(civ_a.call("state_name")), yelps_a])

	# --- Case B: negative control, wall 2 m in FRONT ------------------------
	var base_b := Vector3(60.0, 0.0, 0.0)
	var wall_b: StaticBody3D = _add_wall(world, base_b + Vector3(0.0, 2.0, -2.0))
	var civ_b := _make_civilian(world, body0, head0, base_b)
	civ_b.set("_idle_ttl", 999.0)
	var player_b := _make_player(world, base_b + Vector3(0.0, 0.0, -4.0))
	await physics_frame
	await physics_frame
	# Precondition: the head ray hits the wall, so the false result is occlusion.
	var head_pre_b: Vector3 = civ_b.global_position + Vector3.UP * SightModel.EYE_HEIGHT_M
	var hit_b: Dictionary = _ray(world, head_pre_b, SightModel.target_point(player_b))
	var blocked_b: bool = not hit_b.is_empty() and hit_b.get("collider") == wall_b
	_check(blocked_b, "B precondition: the 2 m front wall occludes the head->player ray",
		"B precondition: front wall does not occlude (hit=%s)" % str(hit_b.get("collider")))
	var can_see_b: bool = bool(civ_b.call("_can_see", player_b))
	_check(not can_see_b, "B a wall 2 m in front blocks sight (_can_see false)",
		"B a wall 2 m in front did not block sight (_can_see true)")
	for _j: int in range(30):
		await physics_frame
	var state_b: String = str(civ_b.call("state_name"))
	var yelps_b: int = int(civ_b.get("yelps"))
	_check(state_b == "wander" and yelps_b == 0, "B occluded civilian does not flee (state=wander yelps=0)",
		"B occluded civilian fled anyway (state=%s yelps=%d)" % [state_b, yelps_b])

	# --- Case C: body skeleton follows the actor's forward ------------------
	var base_c := Vector3(120.0, 0.0, 0.0)
	var civ_c := _make_civilian(world, body0, head0, base_c)
	civ_c.set("_idle_ttl", 999.0)
	await physics_frame
	await physics_frame
	var skel: Skeleton3D = civ_c.get("_skel") as Skeleton3D
	var skel_ok: bool = skel != null and skel.get_bone_count() > 0
	_check(skel_ok, "C body Skeleton3D present (bones=%d)" % (skel.get_bone_count() if skel != null else -1),
		"C body Skeleton3D missing on the real civilian GLB")
	var facing_dot: float = -2.0
	if skel_ok:
		var actor_forward: Vector3 = -civ_c.global_transform.basis.z
		actor_forward.y = 0.0
		var skel_z: Vector3 = skel.global_transform.basis.z
		skel_z.y = 0.0
		if actor_forward.length() > 0.001 and skel_z.length() > 0.001:
			facing_dot = skel_z.normalized().dot(actor_forward.normalized())
	print("W10A2_CIV: facing skel_global_basis_z=", skel.global_transform.basis.z if skel != null else Vector3.ZERO,
		" actor_forward=", -civ_c.global_transform.basis.z, " dot=", facing_dot)
	_check(facing_dot > 0.9, "C skeleton basis.z follows actor forward (dot=%.4f > 0.9)" % facing_dot,
		"C skeleton basis.z is backwards vs actor forward (dot=%.4f <= 0.9)" % facing_dot)

	# --- Case D: two material binds (body 3 + female head 6) ----------------
	var base_d := Vector3(180.0, 0.0, 0.0)
	var civ_d := _make_civilian(world, FEMALE_BODY, FEMALE_HEAD, base_d)
	civ_d.set("_idle_ttl", 999.0)
	await physics_frame
	await physics_frame
	var mesh_root: Node3D = civ_d.get_node_or_null("MeshRoot") as Node3D
	_check(mesh_root != null, "D MeshRoot present", "D MeshRoot missing")
	var body_mi: MeshInstance3D = null
	var head_mi: MeshInstance3D = null
	if mesh_root != null:
		for n: Node in mesh_root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if mi.mesh.get_surface_count() == BODY_SLOTS:
				body_mi = mi
			elif mi.mesh.get_surface_count() == HEAD_SLOTS:
				head_mi = mi
	var body_surfaces: int = body_mi.mesh.get_surface_count() if body_mi != null else -1
	var head_surfaces: int = head_mi.mesh.get_surface_count() if head_mi != null else -1
	print("W10A2_CIV: bind surfaces body=", body_surfaces, " head=", head_surfaces)
	_check(body_mi != null, "D body mesh has %d surfaces" % BODY_SLOTS,
		"D body mesh not found (surface count %d)" % body_surfaces)
	_check(head_mi != null, "D head mesh has %d surfaces" % HEAD_SLOTS,
		"D head mesh not found (surface count %d)" % head_surfaces)
	var body_over: int = 0
	var head_over: int = 0
	var all_dressed: bool = true
	var all_std: bool = true
	if body_mi != null:
		for s: int in range(body_mi.mesh.get_surface_count()):
			var ov: Material = body_mi.get_surface_override_material(s)
			if ov != null:
				body_over += 1
			var sm := ov as StandardMaterial3D
			if sm == null:
				all_std = false
				all_dressed = false
			elif sm.albedo_texture == null and _is_white(sm.albedo_color):
				all_dressed = false
	if head_mi != null:
		for s: int in range(head_mi.mesh.get_surface_count()):
			var ov2: Material = head_mi.get_surface_override_material(s)
			if ov2 != null:
				head_over += 1
			var sm2 := ov2 as StandardMaterial3D
			if sm2 == null:
				all_std = false
				all_dressed = false
			elif sm2.albedo_texture == null and _is_white(sm2.albedo_color):
				all_dressed = false
	print("W10A2_CIV: surface overrides body=", body_over, " head=", head_over)
	_check(body_over == BODY_SLOTS, "D body %d/%d surfaces carry authored overrides" % [body_over, BODY_SLOTS],
		"D body overrides %d != %d (head slots applied to the body?)" % [body_over, BODY_SLOTS])
	_check(head_over == HEAD_SLOTS, "D female head %d/%d surfaces carry authored overrides" % [head_over, HEAD_SLOTS],
		"D female head overrides %d != %d (body slot list applied to the head?)" % [head_over, HEAD_SLOTS])
	_check(all_std and all_dressed, "D every surface is a StandardMaterial3D that is textured or tinted",
		"D a surface is not StandardMaterial3D or is the default white (std=%s dressed=%s)" % [all_std, all_dressed])

	var shirt_path: String = ""
	if body_mi != null:
		var shirt := body_mi.get_surface_override_material(1) as StandardMaterial3D
		if shirt != null and shirt.albedo_texture != null:
			shirt_path = shirt.albedo_texture.resource_path
	_check(shirt_path.ends_with(SHIRT_ALBEDO_SUFFIX),
		"D body slot 1 albedo is " + SHIRT_ALBEDO_SUFFIX,
		"D body slot 1 albedo is '%s' (want suffix %s)" % [shirt_path, SHIRT_ALBEDO_SUFFIX])
	var head_path: String = ""
	if head_mi != null:
		var headmat := head_mi.get_surface_override_material(3) as StandardMaterial3D
		if headmat != null and headmat.albedo_texture != null:
			head_path = headmat.albedo_texture.resource_path
	_check(head_path.ends_with(HEAD_ALBEDO_SUFFIX),
		"D head slot 3 albedo is " + HEAD_ALBEDO_SUFFIX,
		"D head slot 3 albedo is '%s' (want suffix %s)" % [head_path, HEAD_ALBEDO_SUFFIX])

	var has_stats: bool = civ_d.has_method("material_bind_stats")
	_check(has_stats, "D material_bind_stats() present", "D material_bind_stats() missing (no surface census)")
	var stats: Dictionary = civ_d.call("material_bind_stats") as Dictionary if has_stats else {}
	if stats == null:
		stats = {}
	var total: int = int(stats.get("total", -1))
	var bound: int = int(stats.get("bound", -1))
	var textured: int = int(stats.get("textured", -1))
	var default_white: int = int(stats.get("default_white", -1))
	print("W10A2_CIV: bind_stats total=", total, " bound=", bound, " textured=", textured, " default_white=", default_white)
	_check(total == BODY_SLOTS + HEAD_SLOTS, "D bind_stats.total == %d" % (BODY_SLOTS + HEAD_SLOTS),
		"D bind_stats.total %d != %d" % [total, BODY_SLOTS + HEAD_SLOTS])
	_check(bound == BODY_SLOTS + HEAD_SLOTS, "D bind_stats.bound == %d" % (BODY_SLOTS + HEAD_SLOTS),
		"D bind_stats.bound %d != %d" % [bound, BODY_SLOTS + HEAD_SLOTS])
	_check(textured + 1 == BODY_SLOTS + HEAD_SLOTS, "D bind_stats.textured == %d (+1 tinted MI_Default_Red)" % (BODY_SLOTS + HEAD_SLOTS - 1),
		"D bind_stats.textured %d != %d" % [textured, BODY_SLOTS + HEAD_SLOTS - 1])
	_check(default_white == 0, "D bind_stats.default_white == 0",
		"D bind_stats.default_white %d != 0 (surfaces left glTF white)" % default_white)

	_summary()


func _add_floor(parent: Node3D, size: float) -> void:
	var sb := StaticBody3D.new()
	sb.name = "W10A2Floor"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.4, size)
	cs.shape = box
	sb.add_child(cs)
	sb.position = Vector3(0.0, -0.2, 0.0)
	parent.add_child(sb)


## 2 x 4 x 0.2 m blocker centred at `pos` (top of the slab), on the world layer.
func _add_wall(parent: Node3D, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "W10A2Wall"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 4.0, 0.2)
	cs.shape = box
	sb.add_child(cs)
	sb.position = pos
	parent.add_child(sb)
	return sb


func _make_civilian(parent: Node3D, body: String, head: String, pos: Vector3) -> CharacterBody3D:
	var civ: CharacterBody3D = _civ_script.new() as CharacterBody3D
	civ.setup(body, head, pos)
	civ.position = pos + Vector3(0.0, 0.05, 0.0)
	parent.add_child(civ)
	return civ


func _make_player(parent: Node3D, pos: Vector3) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "W10A2Player"
	p.collision_layer = 2
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0.0, 0.85, 0.0)
	p.add_child(cs)
	p.position = pos + Vector3(0.0, 0.05, 0.0)
	parent.add_child(p)
	p.add_to_group("player")
	return p


func _ray(world: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 1))


func _is_white(c: Color) -> bool:
	return c.r >= 0.99 and c.g >= 0.99 and c.b >= 0.99
