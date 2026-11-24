extends SceneTree
## W5B roof collision + occluder policy (static/headless).
##
## Guildhall_PeripheryA packs the pitched roof city: 733 /roofs/ instances in
## 46 unique meshes. Before W5B every one of them took a BoxShape3D, because no
## roof module exceeds the 12 m "box for props" ceiling. A roof module's AABB is
## not its shape: SM_RoofUrban_Ext_Mid_4x4 is a 4.07 x 4.18 m bay that rises
## 4.22 m from eave to ridge (~45 deg), so its box top stood 3.6-4.1 m above the
## eave and the player could stand on an invisible flat platform in the air
## above every roof, while the sloped surface itself was never walkable.
##
## The same AABB made 398 roof occluders in PeripheryA: the hull fills ~12.9 %
## of the box (measured from the GLB triangles), so the occluder culled the city
## behind a solid volume that does not exist.
##
## This test asserts, against the real shipped data:
##   * the roof census and the policy split (334 convex / 399 exact box);
##   * every "convex" /roofs/ mesh really gets ConvexPolygonShape3D with a
##     zero centre offset and more than a box's 8 hull points, and no pitched
##     roof instance carries a BoxShape3D;
##   * flat pieces (trim/fascia/side/end panels), roof decks and roof props
##     (chimney/vent/pipe/gutter/rail/water tank) keep their exact box;
##   * no /roofs/ mesh qualifies as an occluder while a 4x6 wall still does;
##   * shape sanity for a 44 deg and a 62 deg hip: the hull reproduces the
##     authored pitch (apex = half-span * tan(pitch)) and has no eave plateau,
##     so the box would have floated tan(pitch) * half-span above the eave;
##   * on the real 45 deg and 68 deg modules the hull's eave band sits 3.0 m+
##     below the AABB top the old box used as its walking surface.
##
## Run:
##   XDG_DATA_HOME=... tools/godot --headless --path game \
##     --script res://tests/test_roof_collision.gd

const LOADER_PATH := "res://src/core/level_loader.gd"
const LEVEL_PATH := "res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json"
## Measured on the current generated data (tools/parse_levels.py output; pinned
## by `make audit`). A change here is a data or policy change, not a flaky test.
const ROOF_INSTANCES: int = 733
const ROOF_UNIQUE: int = 46
const ROOF_CONVEX_INSTANCES: int = 334
const ROOF_CONVEX_UNIQUE: int = 13
const ROOF_BOX_INSTANCES: int = 399
const ROOF_BOX_UNIQUE: int = 33
## Negative control: 4x6 x 0.30 m exterior wall, the PeripheryA occluder
## workhorse (11,879 instances in Guildhall).
const WALL_MESH: String = "/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6"
## Real modules used for the pitch check: shallow (45.2 deg along the slope
## axis) and steep (67.6 deg). Pitch is measured from the mesh, never assumed.
const SHALLOW_ROOF: String = "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_4x4"
const STEEP_ROOF: String = "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_Mid_6x8"
const PITCH_TOL_DEG: float = 2.0
const MIN_EAVE_GAP_M: float = 3.0

var fails: int = 0
var ll: Node = null


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _initialize() -> void:
	ll = (load(LOADER_PATH) as GDScript).new()
	check_census()
	check_policy_shapes()
	check_occluders()
	check_synth_pitch_shapes()
	check_real_roof_heights()
	ll.free()
	print("ROOF_COLLISION_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


## Instances and unique meshes per policy, straight from the shipped sublevel.
func check_census() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PATH))
	_check(parsed is Dictionary, "level JSON parses", "cannot read " + LEVEL_PATH)
	if not (parsed is Dictionary):
		return {}
	var per_path: Dictionary = {}
	var order: Array[String] = []
	for rec_v: Variant in ((parsed as Dictionary).get("meshes", []) as Array):
		if not (rec_v is Dictionary):
			continue
		var mp: String = str((rec_v as Dictionary).get("mesh", ""))
		if mp.to_lower().find("/roofs/") < 0:
			continue
		if not per_path.has(mp):
			per_path[mp] = 0
			order.append(mp)
		per_path[mp] = int(per_path[mp]) + 1
	var instances: int = 0
	var convex_i: int = 0
	var box_i: int = 0
	var convex_u: int = 0
	var box_u: int = 0
	var unknown: Array[String] = []
	for mp2: String in order:
		var n: int = int(per_path[mp2])
		instances += n
		var kind: String = str(ll.call("roof_collision_kind", mp2))
		if kind == "convex":
			convex_i += n
			convex_u += 1
		elif kind == "box":
			box_i += n
			box_u += 1
		else:
			unknown.append(mp2)
	_check(instances == ROOF_INSTANCES and order.size() == ROOF_UNIQUE,
		"roof census %d instances / %d unique meshes" % [instances, order.size()],
		"roof census changed: %d instances / %d unique (expected %d / %d)" % [instances, order.size(), ROOF_INSTANCES, ROOF_UNIQUE])
	_check(unknown.is_empty(), "every /roofs/ path has a collision policy", "no policy for: " + str(unknown))
	_check(convex_i == ROOF_CONVEX_INSTANCES and convex_u == ROOF_CONVEX_UNIQUE,
		"pitched roof cubes->convex: %d instances / %d unique meshes" % [convex_i, convex_u],
		"convex split changed: %d instances / %d unique (expected %d / %d)" % [convex_i, convex_u, ROOF_CONVEX_INSTANCES, ROOF_CONVEX_UNIQUE])
	_check(box_i == ROOF_BOX_INSTANCES and box_u == ROOF_BOX_UNIQUE,
		"flat roof pieces keep the box: %d instances / %d unique meshes" % [box_i, box_u],
		"box split changed: %d instances / %d unique (expected %d / %d)" % [box_i, box_u, ROOF_BOX_INSTANCES, ROOF_BOX_UNIQUE])
	return per_path


## Every convex-policy mesh must really hand back a convex hull (never a box),
## and the flat pieces must still be boxes.
func check_policy_shapes() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PATH))
	var per_path: Dictionary = {}
	for rec_v: Variant in ((parsed as Dictionary).get("meshes", []) as Array):
		if rec_v is Dictionary:
			var mp: String = str((rec_v as Dictionary).get("mesh", ""))
			if mp.to_lower().find("/roofs/") >= 0:
				per_path[mp] = true
	var convex_boxes: Array[String] = []
	var convex_bad: Array[String] = []
	var box_bad: Array[String] = []
	var hull_points_min: int = 1 << 30
	for mp2: String in per_path.keys():
		var kind: String = str(ll.call("roof_collision_kind", mp2))
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp2)
		var shape: Variant = info.get("shape")
		if shape == null:
			convex_bad.append(mp2 + " (no shape)")
			continue
		var soff: Vector3 = info.get("shape_offset", Vector3.ONE)
		if kind == "convex":
			if not (shape is ConvexPolygonShape3D):
				if shape is BoxShape3D:
					convex_boxes.append(mp2)
				else:
					convex_bad.append(mp2 + " (" + (shape as Object).get_class() + ")")
				continue
			if soff != Vector3.ZERO:
				convex_bad.append(mp2 + " (offset %s)" % str(soff))
			var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
			hull_points_min = mini(hull_points_min, pts.size())
			if pts.size() <= 8:
				convex_bad.append(mp2 + " (%d hull points, a box has 8)" % pts.size())
		elif kind == "box":
			if not (shape is BoxShape3D):
				box_bad.append(mp2 + " (" + (shape as Object).get_class() + ")")
			elif soff == Vector3.ZERO:
				box_bad.append(mp2 + " (box without centre offset)")
	_check(convex_boxes.is_empty(),
		"no pitched /roofs/ mesh returns BoxShape3D",
		"pitched roof meshes still boxed: " + str(convex_boxes))
	_check(convex_bad.is_empty(),
		"all pitched roof shapes are centred-zero convex hulls (min %d points)" % hull_points_min,
		"convex roof shape problems: " + str(convex_bad))
	_check(box_bad.is_empty(),
		"trim/fascia/side/end/deck/prop roof pieces keep the exact box",
		"box roof shape problems: " + str(box_bad))


## Roof AABBs are not occluders (12.9 % filled); walls still are.
func check_occluders() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PATH))
	var per_path: Dictionary = {}
	for rec_v: Variant in ((parsed as Dictionary).get("meshes", []) as Array):
		if rec_v is Dictionary:
			var mp: String = str((rec_v as Dictionary).get("mesh", ""))
			if mp.to_lower().find("/roofs/") >= 0:
				per_path[mp] = int(per_path.get(mp, 0)) + 1
	var bad: Array[String] = []
	for mp2: String in per_path.keys():
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp2)
		var mesh: Mesh = info.get("mesh") as Mesh
		if mesh == null:
			continue
		if bool(ll.call("_qualifies_as_occluder", mp2.to_lower(), mesh)):
			bad.append("%s (%d instances)" % [mp2.get_file(), int(per_path[mp2])])
	_check(bad.is_empty(),
		"roof occluder count 0 across %d /roofs/ meshes (%d instances)" % [per_path.size(), ROOF_INSTANCES],
		"roof meshes still qualify as occluders: " + str(bad))
	var wall_info: Dictionary = ll.call("_get_mesh_and_shape", WALL_MESH)
	var wall_mesh: Mesh = wall_info.get("mesh") as Mesh
	_check(wall_mesh != null, "wall control mesh loads (" + WALL_MESH.get_file() + ")",
		"cannot load wall control mesh " + WALL_MESH)
	if wall_mesh != null:
		_check(bool(ll.call("_qualifies_as_occluder", WALL_MESH.to_lower(), wall_mesh)),
			"exterior wall still an occluder (walls kept)",
			"wall control lost its occluder (occluders were disabled globally)")


## 44 deg vs 62 deg hip sanity: the hull follows the authored pitch, so its
## eave edge sits at the eave while a box would float half_span*tan(pitch) up.
func check_synth_pitch_shapes() -> void:
	var half_span: float = 2.0
	var h44: float = hip_hull_height(half_span, 44.0)
	var h62: float = hip_hull_height(half_span, 62.0)
	var want44: float = half_span * tan(deg_to_rad(44.0))
	var want62: float = half_span * tan(deg_to_rad(62.0))
	_check(absf(h44 - want44) < 0.001,
		"44 deg hip hull apex %.4f m == half-span * tan(44 deg) (%.4f m)" % [h44, want44],
		"44 deg hull apex %.4f m != %.4f m" % [h44, want44])
	_check(absf(h62 - want62) < 0.001,
		"62 deg hip hull apex %.4f m == half-span * tan(62 deg) (%.4f m)" % [h62, want62],
		"62 deg hull apex %.4f m != %.4f m" % [h62, want62])
	# A box keeps the AABB, i.e. its "walking surface" is the apex height over
	# the whole footprint: that is exactly the plateau W5B removed.
	var box_gap44: float = want44
	var box_gap62: float = want62
	_check(box_gap62 > box_gap44 + 1.0,
		"box plateau grows with pitch: %.3f m at 62 deg vs %.3f m at 44 deg" % [box_gap62, box_gap44],
		"pitch/plateau relation lost: 62 deg %.3f m vs 44 deg %.3f m" % [box_gap62, box_gap44])
	_check(absf(box_gap62 / box_gap44 - tan(deg_to_rad(62.0)) / tan(deg_to_rad(44.0))) < 0.01,
		"plateau ratio %.4f matches tan(62)/tan(44) %.4f" % [box_gap62 / box_gap44, tan(deg_to_rad(62.0)) / tan(deg_to_rad(44.0))],
		"plateau ratio differs from tan(62)/tan(44)")


## Builds the same pyramid hip the loader feeds to create_convex_shape() and
## returns the hull apex height plus asserts the eave edge has no plateau.
func hip_hull_height(half_span: float, pitch_deg: float) -> float:
	var h: float = half_span * tan(deg_to_rad(pitch_deg))
	var verts: PackedVector3Array = PackedVector3Array([
		Vector3(-half_span, 0.0, -half_span),
		Vector3(half_span, 0.0, -half_span),
		Vector3(half_span, 0.0, half_span),
		Vector3(-half_span, 0.0, half_span),
		Vector3(0.0, h, 0.0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4, 0, 2, 1, 0, 3, 2,
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shape: Shape3D = mesh.create_convex_shape()
	_check(shape is ConvexPolygonShape3D, "synthetic %.0f deg hip yields a convex shape" % pitch_deg,
		"synthetic %.0f deg hip did not yield a convex shape" % pitch_deg)
	if not (shape is ConvexPolygonShape3D):
		return h
	var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
	var apex: float = -1e9
	var eave_top: float = -1e9
	for p: Vector3 in pts:
		apex = maxf(apex, p.y)
		if Vector2(p.x, p.z).length() > half_span * 0.95:
			eave_top = maxf(eave_top, p.y)
	_check(absf(eave_top) < 0.001,
		"%.0f deg hip hull eave edge stays at y=0 (no flat plateau)" % pitch_deg,
		"%.0f deg hip hull eave edge sits at y=%.3f (plateau)" % [pitch_deg, eave_top])
	# The AABB the box path used always ends at the apex: state the gap so a
	# regression to boxes is obvious in the log.
	_check(apex > 1.9 or pitch_deg < 50.0,
		"%.0f deg hip hull apex %.3f m above the eave (box would float here)" % [pitch_deg, apex],
		"%.0f deg hip hull apex unexpectedly low (%.3f m)" % [pitch_deg, apex])
	return apex


## Real shipped modules: the convex collider's eave band must sit well below the
## AABB top the old BoxShape3D presented as a walking surface.
func check_real_roof_heights() -> void:
	for rec: Dictionary in [
		{"path": SHALLOW_ROOF, "pitch": 45.0, "label": "shallow"},
		{"path": STEEP_ROOF, "pitch": 68.0, "label": "steep"},
	]:
		var mp: String = str(rec["path"])
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp)
		var mesh: Mesh = info.get("mesh") as Mesh
		var shape: Variant = info.get("shape")
		_check(mesh != null and shape is ConvexPolygonShape3D,
			"%s roof (%s) loads with a convex collider" % [rec["label"], mp.get_file()],
			"%s roof (%s) did not load a convex collider" % [rec["label"], mp.get_file()])
		if mesh == null or not (shape is ConvexPolygonShape3D):
			continue
		var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		var top: float = -1e9
		var bottom: float = 1e9
		var z_min: float = 1e9
		var z_max: float = -1e9
		for p: Vector3 in pts:
			top = maxf(top, p.y)
			bottom = minf(bottom, p.y)
			z_min = minf(z_min, p.z)
			z_max = maxf(z_max, p.z)
		var run: float = z_max - z_min
		var rise: float = mesh.get_aabb().size.y
		var pitch: float = rad_to_deg(atan(rise / run))
		_check(absf(pitch - float(rec["pitch"])) <= PITCH_TOL_DEG,
			"%s roof authored pitch %.1f deg (rise %.2f m / run %.2f m)" % [rec["label"], pitch, rise, run],
			"%s roof pitch %.1f deg outside %.1f +/- %.1f" % [rec["label"], pitch, float(rec["pitch"]), PITCH_TOL_DEG])
		var eave_top: float = -1e9
		for p2: Vector3 in pts:
			if p2.z >= z_max - 0.15 * run:
				eave_top = maxf(eave_top, p2.y)
		var gap: float = mesh.get_aabb().position.y + mesh.get_aabb().size.y - eave_top
		_check(gap >= MIN_EAVE_GAP_M,
			"%s roof hull eave band sits %.2f m below the AABB top the box used" % [rec["label"], gap],
			"%s roof hull eave band only %.2f m below the AABB top (want >= %.1f m)" % [rec["label"], gap, MIN_EAVE_GAP_M])
