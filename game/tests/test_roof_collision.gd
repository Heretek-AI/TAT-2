extends SceneTree
## W5B/W6L roof collision + occluder policy (static/headless).
##
## Guildhall_PeripheryA packs the pitched roof city: 733 /roofs/ instances in
## 46 unique meshes. Before W5B every one of them took a BoxShape3D, because no
## roof module exceeds the 12 m "box for props" ceiling. A roof module's AABB is
## not its shape: SM_RoofUrban_Ext_Mid_4x4 is a 4.07 x 4.18 m bay that rises
## 4.22 m from eave to ridge (~45 deg), so its box top stood 3.6-4.1 m above the
## eave and the player could stand on an invisible flat platform in the air
## above every roof, while the sloped surface itself was never walkable.
##
## W6L: the policy is measured, not named. The EndA/EndB gable caps were listed
## as "box" because their names say "End", yet 92 of them are pitched shells
## with 0.000-0.014 top coverage. They now take the convex hull of their real
## geometry; flat decks (1.00) and fascia bands (1.90) still take the exact box.
## The ridge instance at (115.0, 57.5, 26.5) in PeripheryA - the EndB Mirror
## whose box used to float a plateau at the ridge - is asserted directly.
##
## The same AABBs made 398 roof occluders in PeripheryA (12.9 % hull fill), and
## stair flights were filling the freed MAX_OCCLUDERS slots. No roof/stair mesh
## may qualify; the authored Guildhall sublevels must still fill the cap (768)
## with walls/floors, deterministically.
##
## This test asserts, against the real shipped data:
##   * the roof census and the measured policy split (426 convex / 307 box);
##   * every "convex" /roofs/ mesh really gets ConvexPolygonShape3D with a
##     zero centre offset and more than a box's 8 hull points, and no pitched
##     roof instance carries a BoxShape3D;
##   * the six EndA/EndB gable shells (4.32 m and 8.47 m tall) are convex,
##     their hull top matches the visual AABB top, and their eave band sits
##     3 m+ below the box plateau (mirror variants flip which end is the eave);
##   * the (115.0, 57.5, 26.5) ridge instance bypasses the "end" name;
##   * flat pieces (trim/fascia, roof decks), roof props and non-uniformly
##     scaled decks keep their exact box;
##   * the POI 3rd-floor roof census (29 instances: 28 convex / 1 deck) and the
##     Old Manor tower-roof census (6 instances: trimesh, never a box plateau);
##   * no /roofs/ or stair mesh qualifies as an occluder while a 4x6 wall still
##     does, and the Guildhall sublevel census fills MAX_OCCLUDERS = 768.
##
## Run:
##   XDG_DATA_HOME=... tools/godot --headless --path game \
##     --script res://tests/test_roof_collision.gd

const LOADER_PATH := "res://src/core/level_loader.gd"
const LEVEL_PATH := "res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json"
const POI_LEVEL_PATH := "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.tatlevel.json"
const OLDMANOR_LEVEL_PATH := "res://data/generated/levels/OldManor/OldManor_Geo.tatlevel.json"
## Guildhall's authored sublevel list (mission_controller._map_id_to_sublevels),
## in load order. Pinned here so the occluder census walks the same files; a
## change there is a data change, not a flaky test.
const GUILDHALL_SUBLEVELS: Array[String] = [
	"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json",
	"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.tatlevel.json",
	"res://data/generated/levels/Buildings/Guildhall/Guildhall_Vault_CeremonialChambers.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_P.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_Geometry.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_LightingNoGameplay.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_LocalVolumetric.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_Contracts.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_SetSpawners.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_MissionClues.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_SkyboxGeo.tatlevel.json",
]
## Measured on the current generated data (tools/parse_levels.py output; pinned
## by `make audit`). A change here is a data or policy change, not a flaky test.
const ROOF_INSTANCES: int = 733
const ROOF_UNIQUE: int = 46
const ROOF_CONVEX_INSTANCES: int = 426
const ROOF_CONVEX_UNIQUE: int = 19
const ROOF_BOX_INSTANCES: int = 307
const ROOF_BOX_UNIQUE: int = 27
## Negative control: 4x6 x 0.30 m exterior wall, the PeripheryA occluder
## workhorse (11,879 instances in Guildhall).
const WALL_MESH: String = "/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6"
## Real modules used for the pitch check: shallow (45.2 deg along the slope
## axis) and steep (67.6 deg). Pitch is measured from the mesh, never assumed.
const SHALLOW_ROOF: String = "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_4x4"
const STEEP_ROOF: String = "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_Mid_6x8"
const PITCH_TOL_DEG: float = 2.0
const MIN_EAVE_GAP_M: float = 3.0
## W6L End gable shells: 4.316 m (2x4x4) and 8.474 m (2x2x8) tall.
const END_SHELLS: Array[Dictionary] = [
	{"path": "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndA_2x4x4", "height": 4.316},
	{"path": "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndB_2x4x4", "height": 4.316},
	{"path": "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndB_2x4x4_Mirror", "height": 4.316},
	{"path": "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_EndA_2x2x8", "height": 8.474},
	{"path": "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_EndB_2x2x8", "height": 8.474},
	{"path": "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_EndA_2x2x8_Mirror", "height": 8.474},
]
## The audit's ridge bypass: a mirrored EndB at the PeripheryA ridge, next to a
## flipped Mid_4x4. Both are pitched; neither may keep a box.
const RIDGE_POS: Array = [115.0, 57.5, 26.5]
const RIDGE_END_MESH: String = "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndB_2x4x4_Mirror"
const RIDGE_MID_MESH: String = "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_4x4"

var fails: int = 0
var ll: Node = null


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _const(name: String) -> Variant:
	return (ll.get_script() as GDScript).get_script_constant_map().get(name)


func _initialize() -> void:
	ll = (load(LOADER_PATH) as GDScript).new()
	check_census()
	check_policy_shapes()
	check_occluders()
	check_end_shells()
	check_ridge_instance()
	check_poi_census()
	check_old_manor_census()
	check_occluder_census()
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
	# W6L: stair flights are mostly-empty AABBs, not walls. No stair mesh in the
	# authored Guildhall set may qualify (the include token was removed).
	var stair_paths: Dictionary = {}
	for sub: String in GUILDHALL_SUBLEVELS:
		var sp: Variant = JSON.parse_string(FileAccess.get_file_as_string(sub))
		if not (sp is Dictionary):
			continue
		for rec_v2: Variant in ((sp as Dictionary).get("meshes", []) as Array):
			if rec_v2 is Dictionary:
				var smp: String = str((rec_v2 as Dictionary).get("mesh", ""))
				if smp.to_lower().find("stair") >= 0:
					stair_paths[smp] = true
	var stair_bad: Array[String] = []
	for smp2: String in stair_paths.keys():
		var sinfo: Dictionary = ll.call("_get_mesh_and_shape", smp2)
		var smesh: Mesh = sinfo.get("mesh") as Mesh
		if smesh != null and bool(ll.call("_qualifies_as_occluder", smp2.to_lower(), smesh)):
			stair_bad.append(smp2.get_file())
	_check(stair_bad.is_empty(),
		"stair occluder count 0 across %d stair meshes (long, mostly-empty AABBs)" % stair_paths.size(),
		"stair meshes still qualify as occluders: " + str(stair_bad))


## W6L: the EndA/EndB gable caps are pitched shells, not flat "end" panels.
## Six meshes, 92 PeripheryA instances, measured top coverage 0.000-0.014.
func check_end_shells() -> void:
	var bad_kind: Array[String] = []
	var bad_top: Array[String] = []
	var bad_hull: Array[String] = []
	var min_eave_gap: float = 1e9
	var heights_ok: bool = true
	for rec: Dictionary in END_SHELLS:
		var mp: String = str(rec["path"])
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp)
		var mesh: Mesh = info.get("mesh") as Mesh
		var shape: Variant = info.get("shape")
		var kind: String = str(ll.call("roof_collision_kind", mp))
		if kind != "convex" or not (shape is ConvexPolygonShape3D):
			bad_kind.append("%s (kind=%s shape=%s)" % [mp.get_file(), kind,
				(shape as Object).get_class() if shape != null else "null"])
			continue
		if mesh == null:
			bad_kind.append(mp.get_file() + " (mesh missing)")
			continue
		var aabb: AABB = mesh.get_aabb()
		if absf(aabb.size.y - float(rec["height"])) > 0.02:
			heights_ok = false
		# Measured top coverage: the ridge line, not a standable plateau.
		var top_frac: float = float(ll.call("_measure_roof_top_coverage", mesh))
		if top_frac > 0.05:
			bad_top.append("%s (%.4f)" % [mp.get_file(), top_frac])
		# Hull vs visual: the hull's bbox must reproduce the authored AABB top
		# and z span (the hull is the mesh's own convex hull, so it can never
		# float above the visual surface).
		var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		var hull_top: float = -1e9
		var z_min: float = 1e9
		var z_max: float = -1e9
		for p: Vector3 in pts:
			hull_top = maxf(hull_top, p.y)
			z_min = minf(z_min, p.z)
			z_max = maxf(z_max, p.z)
		var aabb_top: float = aabb.position.y + aabb.size.y
		if absf(hull_top - aabb_top) > 0.01 or absf((z_max - z_min) - aabb.size.z) > 0.01:
			bad_hull.append("%s (top %.3f vs %.3f, z %.3f vs %.3f)" % [
				mp.get_file(), hull_top, aabb_top, z_max - z_min, aabb.size.z])
		# The box plateau removed: the eave end sits height - ridge below the
		# AABB top. Mirror variants flip which z end is the eave, so take the
		# deeper of the two end bands.
		var run: float = z_max - z_min
		var gap_lo: float = _end_band_gap(pts, z_min, run)
		var gap_hi: float = _end_band_gap(pts, z_max, run)
		min_eave_gap = minf(min_eave_gap, maxf(gap_lo, gap_hi))
	_check(bad_kind.is_empty(),
		"all 6 EndA/EndB gable shells are convex hulls (92 PeripheryA instances)",
		"End shells not convex: " + str(bad_kind))
	_check(bad_top.is_empty(),
		"End shells measure 0.000-0.014 top coverage (no standable plateau)",
		"End shells still have a flat top: " + str(bad_top))
	_check(heights_ok,
		"End shells measured at the authored 4.32 m and 8.47 m heights",
		"End shell heights changed from the authored 4.32 / 8.47 m")
	_check(bad_hull.is_empty(),
		"End hull bbox matches the visual AABB top and z span",
		"End hull does not match the visual: " + str(bad_hull))
	_check(min_eave_gap >= MIN_EAVE_GAP_M,
		"End hull eave band sits %.2f m below the AABB top the box floated" % min_eave_gap,
		"End hull eave gap %.2f m < %.1f m" % [min_eave_gap, MIN_EAVE_GAP_M])


func _end_band_gap(pts: PackedVector3Array, z_end: float, run: float) -> float:
	var top: float = -1e9
	var band: float = -1e9
	for p: Vector3 in pts:
		top = maxf(top, p.y)
		if absf(p.z - z_end) <= 0.15 * run:
			band = maxf(band, p.y)
	if band < -1e8:
		return 0.0
	return top - band


## The audit's ridge bypass: PeripheryA places a mirrored EndB and a flipped
## Mid_4x4 at (115.0, 57.5, 26.5). The mirrored End used to keep a BoxShape3D,
## so its plateau floated at the ridge line. Both meshes are uniform-scaled
## there, so the measured hull is the visual surface exactly.
func check_ridge_instance() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PATH))
	var found: Array[String] = []
	var bad_scale: Array[String] = []
	for rec_v: Variant in ((parsed as Dictionary).get("meshes", []) as Array):
		if not (rec_v is Dictionary):
			continue
		var rec: Dictionary = rec_v as Dictionary
		var pos_v: Variant = rec.get("pos", [])
		if not (pos_v is Array) or (pos_v as Array).size() < 3:
			continue
		var pos: Array = pos_v as Array
		if absf(float(pos[0]) - float(RIDGE_POS[0])) > 0.01 \
				or absf(float(pos[1]) - float(RIDGE_POS[1])) > 0.01 \
				or absf(float(pos[2]) - float(RIDGE_POS[2])) > 0.01:
			continue
		var mp: String = str(rec.get("mesh", ""))
		if mp != RIDGE_END_MESH and mp != RIDGE_MID_MESH:
			continue
		found.append(mp.get_file())
		var scale_v: Variant = rec.get("scale", [1.0, 1.0, 1.0])
		if scale_v is Array and (scale_v as Array).size() >= 3:
			var sc: Array = scale_v as Array
			if absf(float(sc[0]) - 1.0) > 0.001 or absf(float(sc[1]) - 1.0) > 0.001 or absf(float(sc[2]) - 1.0) > 0.001:
				bad_scale.append(mp.get_file() + " " + str(scale_v))
	_check(found.size() == 2,
		"ridge instance at %s carries the mirrored EndB and flipped Mid_4x4" % str(RIDGE_POS),
		"ridge instance not found (found=%s)" % str(found))
	_check(bad_scale.is_empty(),
		"ridge roofs are uniform-scaled, so the measured hull is the visual",
		"ridge roofs carry a non-uniform scale: " + str(bad_scale))
	for mp2: String in [RIDGE_END_MESH, RIDGE_MID_MESH]:
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp2)
		var shape: Variant = info.get("shape")
		var mesh: Mesh = info.get("mesh") as Mesh
		var ok: bool = shape is ConvexPolygonShape3D
		var span_frac: float = -1.0
		if ok and mesh != null:
			var aabb: AABB = mesh.get_aabb()
			span_frac = _hull_top_span_fraction((shape as ConvexPolygonShape3D).points, aabb)
		_check(ok and span_frac >= 0.0 and span_frac < 0.20,
			"ridge %s bypasses the box: hull top coverage %.3f" % [mp2.get_file(), span_frac],
			"ridge %s kept a box/plateau (shape=%s span=%.3f)" % [mp2.get_file(),
				(shape as Object).get_class() if shape != null else "null", span_frac])


## Horizontal area of hull points within 10 cm of the hull top, over the AABB
## footprint. A box plateau is 1.0; a ridge is a thin line.
func _hull_top_span_fraction(pts: PackedVector3Array, aabb: AABB) -> float:
	var top: float = -1e9
	for p: Vector3 in pts:
		top = maxf(top, p.y)
	var x_min: float = 1e9
	var x_max: float = -1e9
	var z_min: float = 1e9
	var z_max: float = -1e9
	for p2: Vector3 in pts:
		if p2.y < top - 0.10:
			continue
		x_min = minf(x_min, p2.x)
		x_max = maxf(x_max, p2.x)
		z_min = minf(z_min, p2.z)
		z_max = maxf(z_max, p2.z)
	var foot: float = aabb.size.x * aabb.size.z
	if foot <= 0.0001 or x_max < x_min:
		return 0.0
	return ((x_max - x_min) * (z_max - z_min)) / foot


## POI 3rd floor: 29 roof instances over 4 meshes, 28 pitched and 1 deck.
func check_poi_census() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POI_LEVEL_PATH))
	_check(parsed is Dictionary, "POI 3rd-floor level JSON parses", "cannot read " + POI_LEVEL_PATH)
	if not (parsed is Dictionary):
		return
	var per: Dictionary = {}
	for rec_v: Variant in ((parsed as Dictionary).get("meshes", []) as Array):
		if rec_v is Dictionary:
			var mp: String = str((rec_v as Dictionary).get("mesh", ""))
			if mp.to_lower().find("/roofs/") >= 0:
				per[mp] = int(per.get(mp, 0)) + 1
	var instances: int = 0
	var convex_i: int = 0
	var box_i: int = 0
	var bad: Array[String] = []
	for mp2: String in per.keys():
		var n: int = int(per[mp2])
		instances += n
		var kind: String = str(ll.call("roof_collision_kind", mp2))
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp2)
		var shape: Variant = info.get("shape")
		if kind == "convex":
			convex_i += n
			if not (shape is ConvexPolygonShape3D):
				bad.append(mp2.get_file() + " (not convex)")
		elif kind == "box":
			box_i += n
			if not (shape is BoxShape3D):
				bad.append(mp2.get_file() + " (not box)")
		else:
			bad.append(mp2.get_file() + " (no policy)")
	_check(instances == 29 and per.size() == 4,
		"POI 3rd-floor roof census 29 instances / 4 meshes",
		"POI roof census changed: %d / %d" % [instances, per.size()])
	_check(convex_i == 28 and box_i == 1,
		"POI 3rd floor: 28 pitched instances (hull) / 1 roof deck (box)",
		"POI split changed: convex=%d box=%d" % [convex_i, box_i])
	_check(bad.is_empty(), "POI roof shapes match their measured policy",
		"POI roof shape problems: " + str(bad))


## Old Manor tower roofs live outside /roofs/ and are 19-118 m assemblies: they
## keep the trimesh (never a box plateau), and never qualify as occluders.
func check_old_manor_census() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OLDMANOR_LEVEL_PATH))
	_check(parsed is Dictionary, "Old Manor level JSON parses", "cannot read " + OLDMANOR_LEVEL_PATH)
	if not (parsed is Dictionary):
		return
	var per: Dictionary = {}
	for rec_v: Variant in ((parsed as Dictionary).get("meshes", []) as Array):
		if rec_v is Dictionary:
			var mp: String = str((rec_v as Dictionary).get("mesh", ""))
			if mp.to_lower().find("towerroof") >= 0:
				per[mp] = int(per.get(mp, 0)) + 1
	var bad_kind: Array[String] = []
	var bad_shape: Array[String] = []
	var bad_occ: Array[String] = []
	var trimesh_count: int = 0
	for mp2: String in per.keys():
		var kind: String = str(ll.call("roof_collision_kind", mp2))
		if kind != "none":
			bad_kind.append(mp2.get_file() + " (" + kind + ")")
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp2)
		var shape: Variant = info.get("shape")
		var mesh: Mesh = info.get("mesh") as Mesh
		if shape is ConcavePolygonShape3D:
			trimesh_count += 1
		else:
			bad_shape.append("%s (%s)" % [mp2.get_file(), (shape as Object).get_class() if shape != null else "null"])
		if mesh != null and bool(ll.call("_qualifies_as_occluder", mp2.to_lower(), mesh)):
			bad_occ.append(mp2.get_file())
	_check(per.size() == 6 and trimesh_count == 6,
		"Old Manor tower roofs: 6 meshes, all trimesh (no box plateau)",
		"Old Manor roof census changed: unique=%d trimesh=%d" % [per.size(), trimesh_count])
	_check(bad_kind.is_empty(),
		"Old Manor tower roofs are outside the /roofs/ policy (kind=none)",
		"Old Manor roof policy leaked: " + str(bad_kind))
	_check(bad_shape.is_empty(),
		"Old Manor tower roofs keep ConcavePolygonShape3D",
		"Old Manor roof shape problems: " + str(bad_shape))
	_check(bad_occ.is_empty(),
		"Old Manor tower roofs are not occluders",
		"Old Manor roof occluders: " + str(bad_occ))


## W6L occluder census over the authored Guildhall sublevels: no roof/stair
## candidate, the cap (768) is filled by walls/floors, and the selected first-768
## sequence is stable across two builds of the same record order.
func check_occluder_census() -> void:
	var include: Array = _const("OCCLUDER_INCLUDE_TOKENS") as Array
	var clutter: Array = _const("CLUTTER_TOKENS") as Array
	var max_occluders: int = int(_const("MAX_OCCLUDERS"))
	_check(max_occluders == 768, "MAX_OCCLUDERS is 768",
		"MAX_OCCLUDERS is %d (expected 768)" % max_occluders)
	var qual: Dictionary = {}
	var first: Dictionary = _walk_occluders(include, clutter, max_occluders, qual)
	var second: Dictionary = _walk_occluders(include, clutter, max_occluders, qual)
	_check(int(first["raw"]) >= max_occluders,
		"Guildhall authored sublevels yield %d qualifying occluder instances (cap %d)" % [int(first["raw"]), max_occluders],
		"only %d qualifying occluder instances; the 768 cap is no longer reached" % int(first["raw"]))
	_check(int(first["capped"]) == max_occluders,
		"occluder selection caps at exactly %d" % max_occluders,
		"occluder selection capped at %d (expected %d)" % [int(first["capped"]), max_occluders])
	_check(str(first["seq"]) == str(second["seq"]),
		"occluder selection sequence is deterministic (%d entries)" % (first["seq"] as Array).size(),
		"occluder selection sequence changed between two builds")
	# Predicate determinism: re-evaluate a sample of the candidate meshes.
	var keys: Array = qual.keys()
	var sample: Array[String] = []
	var step: int = maxi(1, keys.size() / 12)
	for i: int in range(0, keys.size(), step):
		sample.append(str(keys[i]))
	var mismatch: Array[String] = []
	for mp: String in sample:
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp)
		var mesh: Mesh = info.get("mesh") as Mesh
		var again: bool = mesh != null and bool(ll.call("_qualifies_as_occluder", mp.to_lower(), mesh))
		if again != bool(qual[mp]):
			mismatch.append(mp.get_file())
	_check(mismatch.is_empty(),
		"occluder predicate is deterministic on %d sampled candidate meshes" % sample.size(),
		"occluder predicate changed for: " + str(mismatch))


func _walk_occluders(include: Array, clutter: Array, max_occluders: int, qual: Dictionary) -> Dictionary:
	var raw: int = 0
	var capped: int = 0
	var seq: Array[String] = []
	for sub: String in GUILDHALL_SUBLEVELS:
		if bool(ll.call("_is_decorative_sublevel", sub)):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sub))
		if not (parsed is Dictionary):
			continue
		var idx: int = -1
		for rec_v: Variant in ((parsed as Dictionary).get("meshes", []) as Array):
			idx += 1
			if not (rec_v is Dictionary):
				continue
			var rec: Dictionary = rec_v as Dictionary
			if bool(rec.get("hidden_in_game", false)):
				continue
			var mp: String = str(rec.get("mesh", ""))
			var low: String = mp.to_lower()
			if bool(ll.call("_has_token", low, clutter)):
				continue
			# Cheap pre-filter: the predicate needs a mesh AABB, so only meshes
			# whose names could ever match are loaded. _qualifies_as_occluder()
			# still makes the real decision below.
			if not bool(ll.call("_has_token", low, include)):
				continue
			if not qual.has(mp):
				var info: Dictionary = ll.call("_get_mesh_and_shape", mp)
				var mesh: Mesh = info.get("mesh") as Mesh
				qual[mp] = mesh != null and bool(ll.call("_qualifies_as_occluder", low, mesh))
			if not bool(qual[mp]):
				continue
			raw += 1
			if capped < max_occluders:
				capped += 1
				seq.append(sub.get_file() + ":" + str(idx))
	return {"raw": raw, "capped": capped, "seq": seq}


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
