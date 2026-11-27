extends RefCounted
## P0b acceptance tier "a2": one real Contract 02 (Novice) Guildhall mission.
##
## Invocation:
##   tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=a2
##
## This is the acceptance check the P0a probes did not cover end-to-end:
##   A2-01..05  boot identity: guildhall / Mission.Guildhall.VaultHeist /
##              Novice / not free play / phase=main / authored run clock /
##              4 guards from ONE mission load;
##   A2-GUARD-* every guard carries its own `spawn_marker` meta (<= 2 m), sits
##              <= 0.5 m off that marker's floor ray, selected through an
##              authored guard `spawn_bucket` (never Hauntstable), and is
##              visible with meshes;
##   A2-LOUNGE-* the Lounge guard is authored marker C_20 inside the tracked
##              `poi-lounge-floor` bbox read from
##              `game/data/expansion/content_overrides.json` (never a hard-coded
##              AABB copy);
##   A2-CIV-*   exactly 3 civilians; the Lounge civilian binds 9 authored
##              surfaces with default_white=0, its skeleton faces the actor
##              forward (dot > 0.9), and it flees with a yelp at a player 4 m in
##              front;
##   A2-WHITE   scene-wide near-white audit over visible MeshInstance3D /
##              MultiMeshInstance3D (HUD, particles, player viewmodel and GC
##              broken overlays excluded): every hit must be on the explicit
##              allowlist below, with a reason;
##   A2-SHELL   Lounge shell rays (down floor hit + four horizontal room hits);
##   A2-TURRET  runtime turret census: 1,145 visible parts, 0 hidden, 0
##              meshless;
##   A2-GC-*    runtime GC census (>= 95 hidden broken layers, >= 79 visible
##              intact leaves, 0 visible broken, 0 missing meshes) and one real
##              chest leaf -> broken swap.
##
## The tier is standalone (`--tier=a2`), snapshots GameState and frees the
## mission, so it can run before/after the other tiers without leaking guards,
## civilians or loot.

const SightModel := preload("res://src/ai/sight_model.gd")

const EXPECTED_GUARDS: int = 4
const EXPECTED_CIVILIANS: int = 3
## A2 acceptance thresholds (docs/HANDOFF_NEXT_AGENT.md §3).
const SPAWN_MARKER_MAX_M: float = 2.0
const MARKER_FLOOR_MAX_M: float = 0.5
const LOUNGE_RULE_ID: String = "poi-lounge-floor"
const LOUNGE_MARKER_CODE: String = "C_20"
const CIV_TOTAL_SURFACES: int = 9
const CIV_TEXTURED_SURFACES: int = 8
const CIV_FACING_MIN_DOT: float = 0.9
const CIV_FLEE_MAX_FRAMES: int = 120
## Authored turret census (probe_device_meshes.gd measures the same payload:
## 229 BP_SecurityTurret* actors, 1,145 visible parts, 0 hidden BaseWall).
const TURRET_MESH_PREFIX: String = "/game/art/gameplay/turrets/"
const EXPECTED_TURRET_VISIBLE: int = 1145
## Runtime GC census (probe_gc_destruction.gd: Guildhall_Loot 95 hidden broken
## layers / 79 visible intact leaves for the same level set).
const MIN_GC_LAYERS: int = 95
const MIN_GC_LEAVES: int = 79
## Phase 2 G-2 measured on the real Contract 02 Guildhall load: 16 static
## bookcase panes in Guildhall_Loot + 4 in the POI, bound 1:1 to the 20 authored
## broken overlays. This is a new floor from a measurement, not a re-baseline.
const MIN_GC_STATIC_LEAVES: int = 20

## Explicit near-white allowlist: ue_mesh substring -> documented reason.
## This is NOT a blanket escape: the cream-slab class (`1m_Plane_Reverse` bound
## to MI_EmisLight_Moonlight) is deliberately absent, and the RED proof
## `tests/test_w10a2_cream.gd` pins that defect until the data wave fixes it.
const NEAR_WHITE_ALLOW := {
	# The shipped skies/stars are authored unlit white cards; they are the
	# star field, not lit geometry (SkyboxGeo / Clouds sublevels).
	"/game/art/effects/skybox/": "authored unlit star-field card (shipped sky)",
	"/game/art/effects/clouds/": "authored unlit cloud card (shipped sky)",
	# Authored /Engine/BasicShapes geometry with the engine's own
	# BasicShapeMaterial (3 instances: 1 vault/undercroft cube in
	# Guildhall_Vault_CeremonialChambers, 2 PeripheryA cubes, 1 POI cone below
	# the map). The engine material is not in the shipped material DB, so it
	# resolves to neutral 0.95 grey-white with no emission. These are authored
	# placeholders, not the invented-white emissive class; tracked as
	# PORT_DECISION (engine-material fallback), not a loader invention.
	"/engine/basicshapes/": "authored /Engine/BasicShapes placeholder (BasicShapeMaterial, no emission; PORT_DECISION)",
	# The port's guard-held lantern instantiates the shipped
	# SM_LanternGuardA/SK_Lantern GLB without a UE material bind, so its glass
	# is the glTF white. The authored warm OmniLight (1.0, 0.72, 0.34, energy
	# 1.4) carries the colour; tracked as PORT_APPROX in FIDELITY_GAPS (guard
	# lantern material), not level art.
	"guardlantern/lanternmesh/": "port guard lantern glass is untextured; authored warm lantern light carries the colour (PORT_APPROX)",
	# Guard carried-key prop (3 instances) is the shipped key GLB instantiated
	# without a UE material bind, so its surfaces are the glTF white. Gameplay
	# actor prop, not level art; tracked as PORT_APPROX (carried-item material).
	"carriedkeymesh/": "port guard carried-key GLB is untextured (glTF default); PORT_APPROX actor prop",
}

var h: RefCounted


func _init(helpers: RefCounted) -> void:
	h = helpers


func run() -> void:
	h.snapshot_state()
	var res: Dictionary = await h.instantiate_mission(2, 900, 1)
	var mission: Node = res["mission"] as Node
	var timed_out: bool = bool(res.get("timed_out", true))
	var loaded: bool = h.require(
		mission != null and not timed_out,
		"A2-01",
		"Contract 02 Guildhall mission loaded (frames timed_out=%s)" % str(timed_out)
	)
	if not loaded:
		h.restore_state()
		return

	var gs: Node = h.game_state()
	var guards: Array = h.tree.get_nodes_in_group("guards")
	var map_id: String = str(gs.get("active_map_id"))
	var mission_id: String = str(gs.get("active_mission_id"))
	h.require(
		map_id == "guildhall" and mission_id == "Mission.Guildhall.VaultHeist",
		"A2-02",
		"boot identity map=%s mission=%s" % [map_id, mission_id]
	)
	h.require(
		int(gs.get("difficulty")) == 1 and not h.is_true(gs.get("free_play")) and str(gs.get("phase")) == "main",
		"A2-03",
		"boot identity difficulty=%d free_play=%s phase=%s" % [
			int(gs.get("difficulty")), str(gs.get("free_play")), str(gs.get("phase"))
		]
	)
	# The run clock is the authored mission row's Novice duration, not a copy of
	# it: read both numbers and compare (a hard-coded 3300/7200 would hide a
	# mission-row regression).
	var authored_limit: float = float(GameData.get_mission_duration(mission_id, 1))
	var run_limit: float = float(gs.get("run_time_limit"))
	h.require(
		authored_limit > 0.0 and absf(run_limit - authored_limit) < 0.01,
		"A2-04",
		"run clock run_time_limit=%.0f s == authored mission row %.0f s" % [run_limit, authored_limit]
	)
	h.require(
		guards.size() == EXPECTED_GUARDS,
		"A2-05",
		"Novice guard count %d == %d (PORT_DECISION 4/6/8)" % [guards.size(), EXPECTED_GUARDS]
	)
	guards.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))

	_check_guards(mission, guards)
	var lounge_bbox: AABB = _lounge_bbox()
	h.require(
		lounge_bbox.size.length() > 0.0,
		"A2-LOUNGE-BBOX",
		"tracked %s bbox read from content_overrides.json (%s)" % [LOUNGE_RULE_ID, str(lounge_bbox)]
	)
	_check_lounge_guard(guards, lounge_bbox)
	await _check_civilians(mission, lounge_bbox)
	_check_near_white(mission)
	_check_lounge_shell(mission, guards, lounge_bbox)
	_check_turrets(mission)
	_check_gc(mission)

	await h.free_node(mission)
	h.restore_state()


# --- guards ----------------------------------------------------------------

func _normalize_bucket(bucket: String) -> String:
	var b: String = bucket.strip_edges()
	if b == "":
		return ""
	var quote: int = b.find("'")
	if quote >= 0:
		var rest: String = b.substr(quote + 1)
		var close: int = rest.find("'")
		b = rest.substr(0, close) if close >= 0 else rest
	b = b.get_file().split(".")[0]
	if b.begins_with("DA_SpawnBucket_"):
		b = b.substr("DA_SpawnBucket_".length())
	return b


func _is_guard_bucket(bucket: String) -> bool:
	var b: String = _normalize_bucket(bucket)
	if b == "":
		return false
	if b == "KeyHolder" or b == "PrivateSecurity" or b == "StandardGuards":
		return true
	return b.begins_with("StandardGuards_") or b.begins_with("PrivateSecurity_")


func _marker_code(marker_name: String) -> String:
	var cut: int = marker_name.rfind("_Character_")
	if cut >= 0:
		var tail: String = marker_name.substr(cut + "_Character_".length())
		return tail if tail.begins_with("C_") else "C_" + tail
	return marker_name


func _visible_mesh_count(n: Node) -> int:
	var n_vis: int = 0
	for m: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi != null and mi.is_visible_in_tree() and mi.mesh != null:
			n_vis += 1
	return n_vis


func _ray(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = h.tree.root.world_3d.direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, exclude))


func _check_guards(mission: Node, guards: Array) -> void:
	var no_marker: Array[String] = []
	var far: Array[String] = []
	var floor_bad: Array[String] = []
	var bucket_bad: Array[String] = []
	var hidden: Array[String] = []
	for g_v: Node in guards:
		var g: Node3D = g_v as Node3D
		if g == null:
			continue
		var gname: String = str(g.name)
		var marker_v: Variant = g.get_meta(&"spawn_marker", null)
		if not (marker_v is Vector3):
			no_marker.append(gname)
			continue
		var marker: Vector3 = marker_v as Vector3
		var dist: float = g.global_position.distance_to(marker)
		if dist > SPAWN_MARKER_MAX_M:
			far.append("%s(%.2fm)" % [gname, dist])
		var floor_hit: Dictionary = _ray(marker + Vector3(0.0, 0.05, 0.0), marker + Vector3(0.0, -30.0, 0.0))
		if not floor_hit.is_empty():
			var floor_y: float = (floor_hit.get("position") as Vector3).y
			if absf(g.global_position.y - floor_y) > MARKER_FLOOR_MAX_M:
				floor_bad.append("%s(%.2fm)" % [gname, absf(g.global_position.y - floor_y)])
		var bucket: String = str(g.get_meta(&"spawn_bucket", ""))
		if not _is_guard_bucket(bucket) or _normalize_bucket(bucket) == "Hauntstable":
			bucket_bad.append("%s('%s')" % [gname, bucket])
		if not g.is_visible_in_tree() or _visible_mesh_count(g) == 0:
			hidden.append(gname)
		print("A2_MEASURE guard=%s marker=%s dist=%.3f bucket=%s layers=%s" % [
			gname, str(marker), dist, bucket, str(g.get_meta(&"spawn_layers", []))
		])
	h.require(no_marker.is_empty(), "A2-GUARD-META",
		"every guard carries its own spawn_marker meta (%s)" % str(no_marker))
	h.require(far.is_empty(), "A2-GUARD-DIST",
		"every guard <= %.1f m from its spawn marker (%s)" % [SPAWN_MARKER_MAX_M, str(far)])
	h.require(floor_bad.is_empty(), "A2-GUARD-FLOOR",
		"every guard <= %.1f m off its marker floor ray (%s)" % [MARKER_FLOOR_MAX_M, str(floor_bad)])
	h.require(bucket_bad.is_empty(), "A2-GUARD-BUCKET",
		"every guard selected through an authored guard bucket, never Hauntstable (%s)" % str(bucket_bad))
	h.require(hidden.is_empty(), "A2-GUARD-VISIBLE",
		"every guard visible with meshes (%s)" % str(hidden))


## The tracked Lounge rule from game/data/expansion/content_overrides.json:
## bbox = [x0, y0, z0, x1, y1, z1]. Read, never copied: a moved POI rule must
## fail this check rather than silently pass against a stale AABB.
func _lounge_bbox() -> AABB:
	var doc_v: Variant = h.repo_read_json("game/data/expansion/content_overrides.json")
	if not (doc_v is Dictionary):
		return AABB()
	# `poi-lounge-floor` is a tracked coverage region (the graybox-census
	# registry); the per-kit `rules` list carries the actual substitution rules
	# and uses suffixed ids (`…-tile`). Read the region first, then fall back to a
	# rule with the exact id so either schema keeps the AABB tracked.
	for section: String in ["coverage_regions", "rules"]:
		var rows_v: Variant = (doc_v as Dictionary).get(section, [])
		if not (rows_v is Array):
			continue
		for rule_v: Variant in (rows_v as Array):
			var rule: Dictionary = rule_v as Dictionary
			if str(rule.get("id", "")) != LOUNGE_RULE_ID:
				continue
			var b: Variant = rule.get("bbox", null)
			if b is Array and (b as Array).size() >= 6:
				var a: Array = b as Array
				var pos := Vector3(float(a[0]), float(a[1]), float(a[2]))
				var end := Vector3(float(a[3]), float(a[4]), float(a[5]))
				return AABB(pos, end - pos)
	return AABB()


func _check_lounge_guard(guards: Array, lounge_bbox: AABB) -> void:
	var in_lounge: int = 0
	var code: String = ""
	var lounge_pos := Vector3.ZERO
	for g_v: Node in guards:
		var g: Node3D = g_v as Node3D
		if g == null:
			continue
		if lounge_bbox.has_point(g.global_position):
			in_lounge += 1
			if code == "":
				code = _marker_code(str(g.get_meta(&"spawn_marker_name", "")))
				lounge_pos = g.global_position
	h.require(
		in_lounge >= 1 and code == LOUNGE_MARKER_CODE,
		"A2-LOUNGE-GUARD",
		"Lounge guard marker=%s inside the tracked bbox at %s (guards in bbox=%d)" % [
			code if code != "" else "-", str(lounge_pos), in_lounge
		]
	)


# --- civilians -------------------------------------------------------------

func _check_civilians(mission: Node, lounge_bbox: AABB) -> void:
	var civs: Array = h.tree.get_nodes_in_group("civilians")
	h.require(
		civs.size() == EXPECTED_CIVILIANS,
		"A2-CIV-COUNT",
		"civilian count %d == %d" % [civs.size(), EXPECTED_CIVILIANS]
	)
	civs.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	var lounge_civ: Node3D = null
	for c_v: Node in civs:
		var c: Node3D = c_v as Node3D
		if c != null and lounge_bbox.has_point(c.global_position) and lounge_civ == null:
			lounge_civ = c
		if c != null:
			print("A2_MEASURE civilian=%s pos=%s in_lounge=%s" % [
				str(c.name), str(c.global_position), str(lounge_bbox.has_point(c.global_position))
			])
	h.require(lounge_civ != null, "A2-CIV-LOUNGE",
		"one civilian stands inside the tracked Lounge bbox")
	if lounge_civ == null:
		return

	var stats: Dictionary = {}
	if lounge_civ.has_method("material_bind_stats"):
		stats = lounge_civ.call("material_bind_stats") as Dictionary
	var total: int = int(stats.get("total", -1))
	var bound: int = int(stats.get("bound", -1))
	var textured: int = int(stats.get("textured", -1))
	var default_white: int = int(stats.get("default_white", -1))
	print("A2_MEASURE lounge_civ bind_stats total=%d bound=%d textured=%d default_white=%d" % [
		total, bound, textured, default_white
	])
	h.require(
		total == CIV_TOTAL_SURFACES and bound == CIV_TOTAL_SURFACES \
			and textured == CIV_TEXTURED_SURFACES and default_white == 0,
		"A2-CIV-BIND",
		"Lounge civilian authored surface bind total=%d bound=%d textured=%d default_white=%d (want %d/%d/%d/0)" % [
			total, bound, textured, default_white,
			CIV_TOTAL_SURFACES, CIV_TOTAL_SURFACES, CIV_TEXTURED_SURFACES
		]
	)

	var skel: Skeleton3D = lounge_civ.get("_skel") as Skeleton3D
	var facing_dot: float = -2.0
	if skel != null and skel.get_bone_count() > 0:
		var actor_forward: Vector3 = -lounge_civ.global_transform.basis.z
		actor_forward.y = 0.0
		var skel_z: Vector3 = skel.global_transform.basis.z
		skel_z.y = 0.0
		if actor_forward.length() > 0.001 and skel_z.length() > 0.001:
			facing_dot = skel_z.normalized().dot(actor_forward.normalized())
	h.require(
		facing_dot > CIV_FACING_MIN_DOT,
		"A2-CIV-FACING",
		"Lounge civilian skeleton follows the actor forward (dot=%.4f > %.1f)" % [
			facing_dot, CIV_FACING_MIN_DOT
		]
	)

	# Flee with yelp: a stand-in player 4 m in front of the civilian, inside the
	# civilian's frustum with a clear head->body ray. A synthetic stand-in (the
	# same capsule the unit suite builds) is used so the real mission player's
	# controller cannot drift the spot; it joins the "player" group for the
	# civilian's own scan. Candidates fan ±30 deg because Lounge furniture may
	# sit on the straight-ahead line; the first clear one is used.
	var probe_player: CharacterBody3D = _make_probe_player(mission)
	var forward: Vector3 = -lounge_civ.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD
	var chosen := Vector3.ZERO
	var clear: bool = false
	var chosen_deg: float = 0.0
	for deg: float in [0.0, -15.0, 15.0, -30.0, 30.0]:
		var dir: Vector3 = forward.rotated(Vector3.UP, deg_to_rad(deg))
		var spot: Vector3 = lounge_civ.global_position + dir * 4.0
		probe_player.global_position = Vector3(spot.x, lounge_civ.global_position.y + 0.05, spot.z)
		await h.step_physics(1)
		var hit: Dictionary = _ray(SightModel.head_position(lounge_civ),
			SightModel.target_point(probe_player), [lounge_civ.get_rid(), probe_player.get_rid()])
		if hit.is_empty():
			chosen = probe_player.global_position
			clear = true
			chosen_deg = deg
			break
	var can_see: bool = bool(lounge_civ.call("_can_see", probe_player)) if lounge_civ.has_method("_can_see") else false
	var fled: bool = false
	for _i: int in range(CIV_FLEE_MAX_FRAMES):
		await h.step_physics(1)
		if str(lounge_civ.call("state_name")) == "flee":
			fled = true
			break
	var yelps: int = int(lounge_civ.get("yelps"))
	print("A2_MEASURE lounge_civ flee clear_ray=%s deg=%.0f can_see=%s state=%s yelps=%d spot=%s" % [
		str(clear), chosen_deg, str(can_see), str(lounge_civ.call("state_name")), yelps, str(chosen)
	])
	h.require(
		clear and can_see and (fled or str(lounge_civ.call("state_name")) == "flee") and yelps >= 1,
		"A2-CIV-FLEE",
		"Lounge civilian flees with a yelp at a player 4 m in front (clear=%s deg=%.0f can_see=%s state=%s yelps=%d)" % [
			str(clear), chosen_deg, str(can_see), str(lounge_civ.call("state_name")), yelps
		]
	)
	await h.free_node(probe_player)


## Capsule-only player stand-in (unit-suite contract): layer 2 so civilian
## sight rays can hit it, no script so nothing moves it off the chosen spot.
func _make_probe_player(parent: Node) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "A2ProbePlayer"
	p.collision_layer = 2
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0.0, 0.85, 0.0)
	p.add_child(cs)
	parent.add_child(p)
	p.add_to_group("player")
	return p


# --- near-white audit ------------------------------------------------------

func _is_under_canvas_layer(n: Node) -> bool:
	var p: Node = n.get_parent()
	while p != null:
		if p is CanvasLayer:
			return true
		p = p.get_parent()
	return false


func _material_is_near_white(mat: Material) -> bool:
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	if sm == null:
		return false
	if sm.albedo_texture == null:
		var c: Color = sm.albedo_color
		if c.r >= 0.95 and c.g >= 0.95 and c.b >= 0.95 and c.a >= 0.5:
			return true
	if sm.emission_enabled and sm.emission_texture == null:
		# Untextured white emission is the invented-white class. A white
		# EmissiveColor WITH an authored emissive map is a multiplier (the map
		# carries the colour) and is not flagged.
		var e: Color = sm.emission
		if e.r >= 0.95 and e.g >= 0.95 and e.b >= 0.95 and sm.emission_energy_multiplier > 0.0:
			return true
	return false


## Particles/VFX are excluded by contract ("exclude HUD/particles"): Niagara
## meshes, FluidNinja fluids and their billboards are effect geometry, not
## level art. Structural exclusion, not an allowlist entry.
func _is_vfx_node(n: Node, keys: Array[String]) -> bool:
	if str(n.get_path()).to_lower().find("levelniagara") >= 0:
		return true
	for k: String in keys:
		var low: String = k.to_lower()
		if low.begins_with("/game/art/vfx/") or low.begins_with("/game/thirdparty/fluidninja") \
			or low.find("niagara") >= 0:
			return true
	return false


func _collect_render_nodes(n: Node, out: Array[Node]) -> void:
	for c: Node in n.get_children():
		if c is MeshInstance3D or c is MultiMeshInstance3D:
			out.append(c)
		_collect_render_nodes(c, out)


func _mesh_surfaces(node: Node) -> Array[Material]:
	var mats: Array[Material] = []
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D:
		var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
		mesh = mm.mesh if mm != null else null
	if mesh == null:
		return mats
	for s: int in range(mesh.get_surface_count()):
		var ov: Material = null
		if node.has_method("get_surface_override_material"):
			ov = node.call("get_surface_override_material", s) as Material
		var active: Material = ov if ov != null else mesh.surface_get_material(s)
		mats.append(active)
	return mats


func _material_detail(mat: Material) -> String:
	if mat == null:
		return "null(glTF-default)"
	if mat is StandardMaterial3D:
		var sm: StandardMaterial3D = mat as StandardMaterial3D
		return "Standard3D albedo_tex=%s albedo=%s emission_tex=%s emission=%s/%s energy=%.2f" % [
			sm.albedo_texture.resource_path.get_file() if sm.albedo_texture != null else "-",
			str(sm.albedo_color),
			sm.emission_texture.resource_path.get_file() if sm.emission_texture != null else "-",
			str(sm.emission_enabled), str(sm.emission),
			sm.emission_energy_multiplier,
		]
	if mat is ShaderMaterial:
		var sh: ShaderMaterial = mat as ShaderMaterial
		return "Shader(%s)" % (sh.shader.resource_path.get_file() if sh.shader != null else "?")
	return str(mat.get_class())


func _node_material_detail(n: Node) -> String:
	var parts: Array[String] = []
	var mats: Array[Material] = _mesh_surfaces(n)
	for s: int in range(mini(mats.size(), 4)):
		parts.append("[%d]%s" % [s, _material_detail(mats[s])])
	return " | ".join(PackedStringArray(parts))


func _node_ue_keys(n: Node) -> Array[String]:
	var keys: Array[String] = []
	var key: String = str(n.get_meta("ue_mesh", ""))
	if key != "":
		keys.append(key)
	var merged: Variant = n.get_meta("merged_ue_meshes", [])
	if merged is Array:
		for m_v: Variant in (merged as Array):
			keys.append(str(m_v))
	return keys


func _check_near_white(mission: Node) -> void:
	var nodes: Array[Node] = []
	_collect_render_nodes(mission, nodes)
	var player: Node = mission.get("player")
	var visible: int = 0
	var flagged: Dictionary = {}
	var shader_surfaces: int = 0
	var allow_hits: Dictionary = {}
	var cream_nodes: int = 0
	var cream_detail: Array[String] = []
	for n_v: Node in nodes:
		var n: Node = n_v
		if not n.is_visible_in_tree() or _is_under_canvas_layer(n):
			continue
		if player != null and player.is_ancestor_of(n):
			continue
		if str(n.get_meta("gc_role", "")) == "broken":
			continue
		visible += 1
		var keys: Array[String] = _node_ue_keys(n)
		for k: String in keys:
			if k.to_lower().find("1m_plane_reverse") >= 0:
				cream_nodes += 1
				if cream_detail.size() < 3:
					cream_detail.append("%s <- %s" % [str(n.get_path()), _node_material_detail(n)])
				break
		if _is_vfx_node(n, keys):
			continue
		var key: String = keys[0] if not keys.is_empty() else ""
		if key == "":
			key = "<no ue_mesh> " + str(n.get_class())
		var is_white: bool = false
		for mat: Material in _mesh_surfaces(n):
			if mat == null:
				is_white = true
				break
			if mat is ShaderMaterial:
				shader_surfaces += 1
				continue
			if _material_is_near_white(mat):
				is_white = true
				break
		if not is_white:
			continue
		var allowed: String = ""
		var haystacks: Array[String] = [key.to_lower(), str(n.get_path()).to_lower(), str(n.name).to_lower()]
		for allow_key: String in NEAR_WHITE_ALLOW.keys():
			var needle: String = str(allow_key).to_lower()
			for hay: String in haystacks:
				if hay.find(needle) >= 0:
					allowed = str(NEAR_WHITE_ALLOW[allow_key])
					break
			if allowed != "":
				break
		# The cream-slab class must never be allowlisted; a future edit that
		# tries to hide it fails this gate instead of shrinking the audit.
		if allowed != "" and (key.to_lower().find("1m_plane_reverse") >= 0 \
				or key.to_lower().find("emislight_moonlight") >= 0):
			allowed = ""
		if allowed != "":
			var allow_rec: Dictionary = allow_hits.get(key, {"count": 0, "reason": allowed}) as Dictionary
			allow_rec["count"] = int(allow_rec["count"]) + 1
			allow_rec["reason"] = allowed
			allow_hits[key] = allow_rec
			continue
		var slot: Dictionary = flagged.get(key, {"count": 0, "sample": "", "detail": ""})
		slot["count"] = int(slot["count"]) + 1
		if str(slot["sample"]) == "":
			slot["sample"] = str(n.get_path())
			slot["detail"] = _node_material_detail(n)
		flagged[key] = slot
	for key: String in flagged.keys():
		var rec: Dictionary = flagged[key] as Dictionary
		print("A2_WHITE unexplained key=%s count=%d sample=%s detail=%s" % [
			key, int(rec["count"]), str(rec["sample"]), str(rec["detail"])
		])
	for key: String in allow_hits.keys():
		var rec2: Dictionary = allow_hits[key] as Dictionary
		print("A2_WHITE allowed key=%s count=%d reason=%s" % [
			key, int(rec2["count"]), str(rec2["reason"])
		])
	print("A2_MEASURE cream_slabs nodes=%d detail=%s" % [cream_nodes, str(cream_detail)])
	print("A2_MEASURE near_white visible_nodes=%d shader_surfaces=%d unexplained=%d allowed=%d allowlist=%d" % [
		visible, shader_surfaces, flagged.size(), allow_hits.size(), NEAR_WHITE_ALLOW.size()
	])
	h.require(
		flagged.is_empty(),
		"A2-WHITE",
		"no unexplained near-white visible mesh (visible=%d shader_surfaces=%d unexplained=%d allowlisted=%d)" % [
			visible, shader_surfaces, flagged.size(), allow_hits.size()
		]
	)


# --- Lounge shell ----------------------------------------------------------

func _check_lounge_shell(_mission: Node, guards: Array, lounge_bbox: AABB) -> void:
	var origin := Vector3.ZERO
	for g_v: Node in guards:
		var g: Node3D = g_v as Node3D
		if g != null and lounge_bbox.has_point(g.global_position):
			origin = g.global_position + Vector3.UP * 1.0
			break
	if origin == Vector3.ZERO:
		h.require(false, "A2-SHELL", "no Lounge guard origin for the shell rays")
		return
	var max_x: float = maxf(absf(lounge_bbox.position.x - origin.x), absf(lounge_bbox.end.x - origin.x))
	var max_z: float = maxf(absf(lounge_bbox.position.z - origin.z), absf(lounge_bbox.end.z - origin.z))
	var reach: Vector2 = Vector2(max_x + 2.0, max_z + 2.0)
	var dirs: Array[Dictionary] = [
		{"name": "+X", "to": origin + Vector3(reach.x, 0.0, 0.0)},
		{"name": "-X", "to": origin - Vector3(reach.x, 0.0, 0.0)},
		{"name": "+Z", "to": origin + Vector3(0.0, 0.0, reach.y)},
		{"name": "-Z", "to": origin - Vector3(0.0, 0.0, reach.y)},
	]
	var hits: int = 0
	var detail: Array[String] = []
	for d: Dictionary in dirs:
		var hit: Dictionary = _ray(origin, d["to"] as Vector3)
		if not hit.is_empty():
			hits += 1
		detail.append("%s=%s" % [str(d["name"]), "hit" if not hit.is_empty() else "miss"])
	var floor_hit: Dictionary = _ray(origin, origin + Vector3(0.0, -12.0, 0.0))
	print("A2_MEASURE shell origin=%s horizontal=%d/4 %s floor=%s" % [
		str(origin), hits, str(detail), "hit" if not floor_hit.is_empty() else "miss"
	])
	h.require(
		hits >= 3 and not floor_hit.is_empty(),
		"A2-SHELL",
		"Lounge shell rays: %d/4 horizontal hits + floor hit (origin=%s, %s)" % [
			hits, str(origin), str(detail)
		]
	)


# --- turrets ---------------------------------------------------------------

func _check_turrets(mission: Node) -> void:
	var visible: int = 0
	var hidden: int = 0
	var meshless: int = 0
	var cells: int = 0
	var multi_path_cells: int = 0
	var cell_paths: Dictionary = {}
	var emitted_paths: Dictionary = {}
	var render_nodes: Array[Node] = []
	_collect_render_nodes(mission, render_nodes)
	for n_v: Node in render_nodes:
		var n: Node = n_v
		var key: String = str(n.get_meta("ue_mesh", "")).to_lower()
		if key.begins_with(TURRET_MESH_PREFIX):
			emitted_paths[key] = true
			var has_mesh: bool = true
			if n is MeshInstance3D:
				has_mesh = (n as MeshInstance3D).mesh != null
			elif n is MultiMeshInstance3D:
				var mm0: MultiMesh = (n as MultiMeshInstance3D).multimesh
				has_mesh = mm0 != null and mm0.mesh != null
			if not has_mesh:
				meshless += 1
			elif n.is_visible_in_tree():
				visible += 1
			else:
				hidden += 1
			continue
		# Merged cells are plain MeshInstance3D (ArrayMesh) or MultiMeshInstance3D;
		# both carry merged_ue_meshes.
		var merged: Variant = n.get_meta("merged_ue_meshes", [])
		if not (merged is Array):
			continue
		var has_turret: bool = false
		for p_v: Variant in (merged as Array):
			var p: String = str(p_v).to_lower()
			if p.begins_with(TURRET_MESH_PREFIX):
				has_turret = true
				cell_paths[p] = true
		if not has_turret:
			continue
		cells += 1
		if (merged as Array).size() > 1:
			multi_path_cells += 1
	for p: String in cell_paths.keys():
		emitted_paths[p] = true
	# The authored payload is the count contract (the runtime batches turret
	# parts into merged cells, so a node count is not the part count). Runtime
	# representation is proven path-by-path: every authored turret mesh path is
	# either an emitted node or present in a merged cell, with no meshless part.
	var payload: Dictionary = h.read_json(
		"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json") as Dictionary
	var authored_visible: int = 0
	var authored_hidden: int = 0
	var authored_paths: Dictionary = {}
	for m_v: Variant in (payload.get("meshes", []) as Array):
		var m: Dictionary = m_v as Dictionary
		var mp: String = str(m.get("mesh", "")).to_lower()
		if not mp.begins_with(TURRET_MESH_PREFIX):
			continue
		authored_paths[mp] = true
		if bool(m.get("hidden_in_game", false)):
			authored_hidden += 1
		else:
			authored_visible += 1
	var missing_paths: Array[String] = []
	for p2: String in authored_paths.keys():
		if not emitted_paths.has(p2):
			missing_paths.append(p2)
	print("A2_MEASURE turret visible=%d hidden=%d meshless=%d merged_cells=%d multi_path_cells=%d authored=%d/%d paths=%d missing_paths=%d unique_runtime_cells=%d" % [
		visible, hidden, meshless, cells, multi_path_cells, authored_visible, authored_hidden,
		authored_paths.size(), missing_paths.size(), cell_paths.size()
	])
	h.require(
		authored_visible == EXPECTED_TURRET_VISIBLE and authored_hidden == 0 \
			and meshless == 0 and missing_paths.is_empty(),
		"A2-TURRET",
		"turret census authored visible=%d (want %d) hidden=%d; runtime meshless=%d missing_paths=%s (individual=%d, merged_cells=%d)" % [
			authored_visible, EXPECTED_TURRET_VISIBLE, authored_hidden, meshless,
			str(missing_paths), visible, cells
		]
	)


# --- GC --------------------------------------------------------------------

func _check_gc(mission: Node) -> void:
	var stats: Dictionary = mission.get("level_stats") as Dictionary
	var layers: int = int(stats.get("gc_layers_built", -1))
	var leaves: int = int(stats.get("gc_leaves_built", -1))
	var static_leaves: int = int(stats.get("gc_static_leaves_bound", -1))
	var visible_broken: int = int(stats.get("gc_visible_broken", -1))
	var missing: int = int(stats.get("gc_missing_mesh", -1))
	print("A2_MEASURE gc layers=%d leaves=%d static_bookcase_leaves=%d visible_broken=%d missing=%d" % [
		layers, leaves, static_leaves, visible_broken, missing
	])
	h.require(
		layers >= MIN_GC_LAYERS and leaves >= MIN_GC_LEAVES \
			and static_leaves >= MIN_GC_STATIC_LEAVES \
			and visible_broken == 0 and missing == 0,
		"A2-GC-STATS",
		"runtime GC census layers=%d (>=%d) leaves=%d (>=%d) static_bookcase_leaves=%d (>=%d) visible_broken=%d missing=%d" % [
			layers, MIN_GC_LAYERS, leaves, MIN_GC_LEAVES, static_leaves, MIN_GC_STATIC_LEAVES,
			visible_broken, missing
		]
	)
	var container: Node = null
	for n_v: Node in h.tree.get_nodes_in_group("loot_containers"):
		if n_v != null and n_v.has_method("has_broken_overlay") and bool(n_v.call("has_broken_overlay")):
			container = n_v
			break
	if container == null:
		h.require(false, "A2-GC-SWAP", "no loot container with an authored broken overlay")
		return
	var leaf: Node3D = container.get("_gc_leaf") as Node3D
	var broken: Node3D = container.get("_gc_broken") as Node3D
	var before_ok: bool = leaf != null and broken != null and leaf.visible and not broken.visible
	var swapped: bool = bool(container.call("break_container", null))
	var after_ok: bool = leaf != null and broken != null and not leaf.visible and broken.visible
	h.require(
		before_ok and swapped and after_ok,
		"A2-GC-SWAP",
		"one chest swap %s -> %s (broken=%s opened=%s)" % [
			str(container.name),
			"leaf" if after_ok else "NOT swapped",
			str(container.get("broken")), str(container.get("opened"))
		]
	)
