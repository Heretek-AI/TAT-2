extends Node3D
## P1-BEAMS: KF27 / V6-03 / V4-07 foyer dressing repair.
##
## The shipped foyer already carries most of its authored dressing in the POI
## sublevel (Building_Guildhall_POI): the tall glass statue vitrine
## (SM_Museum_DisplayCase_2x2_Tall_01..05 + SM_GuardEnforcer_Salute), the
## armchair/ottoman pair (SM_SofaFancyA + SM_StoolA at the foyer threshold) and
## the two wooden sign plates. What the port was missing:
##   * the wall emitter's bulb renders through the glass path with no emission,
##     so the circular emitter is a dark blob instead of KF27#1's glow;
##   * the cyan junction node's only exported record is a `hidden_in_game`
##     light-module proxy (SM_Sphere2Count); the visible KF27 node is a
##     Blueprint/Niagara overlay, so the port has no visible node;
##   * the BP_SignPlate3D Text3DComponents ("Basement\r\n Stairs", "WC") are
##     not exported as meshes, so both plaques are blank (V4-07 legibility);
##   * the flush floor plate has an authored mesh (SM_FloorPlate) but no
##     authored placement anywhere in the exported POI level data.
##
## This node repairs the materials, draws the authored plaque text, places the
## floor plate and draws the visible cyan node. The floor-plate placement, the
## node visual size and the plaque font are PORT_APPROX; everything else is an
## authored value or an authored mesh.
##
## NOT authored / NOT touched here: the security tripwire logic (HL-3), the
## Niagara laser beam renderer (HL-1; the fallback is security_beam.gd) and the
## point light in BP_Detector_LightBeam (authored 0.01 lm / 0.35 m, i.e. a
## sub-centimetre glow that is not visible at foyer distances).

const BULB_SUFFIX: String = "SM_LightBeam_Bulb"
const NODE_MESH_SUFFIX: String = "SM_Sphere2Count"
const BULB_UE: String = "/Game/Art/Gameplay/LightBeam/SM_LightBeam_Bulb"
const NODE_UE: String = "/Game/Art/Environment/Lights/LightModules/EmissiveShapes/SM_Sphere2Count"
const FLOOR_PLATE_UE: String = "/Game/Art/Environment/Urban/Industrial/SM_FloorPlate"

## MI_LightBeam authored emissive colour (vectors.Emissive Color) x
## params.Brightness. The bulb is the white-warm disc at KF27#1.
const BULB_EMISSIVE: Color = Color(1.0, 0.6892, 0.2661)
const BULB_BRIGHTNESS: float = 2.0
## Authored cool node light colour (POI lights record 82A7FF at
## 28.8973, 30.1446, -58.4065; B=255 G=167 R=130).
const NODE_LIGHT_COLOR: Color = Color(130.0 / 255.0, 167.0 / 255.0, 1.0)
## Node mesh placement from Building_Guildhall_POI.tatlevel.json.
const NODE_POS: Vector3 = Vector3(28.8973, 30.4025, -58.002)
## The exported shape is a hidden light-module proxy (2.5 m wide); KF27 shows
## a compact ~0.30 m tall vertical lozenge above the far doors. The visible
## stand-in is that authored mesh at the KF27 size (PORT_APPROX geometry).
const NODE_VISUAL_POS: Vector3 = Vector3(28.8973, 30.1446, -58.4065)
const NODE_VISUAL_SCALE: Vector3 = Vector3(0.03, 0.35, 0.10)
## PORT_APPROX: no authored SM_FloorPlate record exists in the POI export.
## KF27 shows the flush plate at the foyer centre, in front of the vitrine.
const FLOOR_PLATE_POS: Vector3 = Vector3(27.9, 27.94, -50.8)
const FLOOR_PLATE_SCALE: float = 0.6
## Authored Text3DComponent strings (Building_Guildhall_POI.json):
##   BP_SignPlate3D_C_5  "Basement\r\n Stairs" -> SM_InteriorSign_WealthyA
##   BP_SignPlate3D_C_0  "WC"                 -> SM_InteriorSign_CommonC
const PLAQUE_TEXT: Dictionary = {
	"WealthyA": "Basement\nStairs",
	"CommonC": "WC",
}
## Authored plate placements (pos + row-major basis) from the generated POI
## level. The Text3D relative location is (0, 3, 0) cm in the plate frame.
const PLAQUES: Array = [
	{
		"key": "WealthyA",
		"pos": Vector3(30.72, 30.74, -45.79),
		"basis": [0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0],
	},
	{
		"key": "CommonC",
		"pos": Vector3(28.92, 30.67, -58.70),
		"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
	},
]

var stats: Dictionary = {
	"emitter_bulbs": 0,
	"node_items": 0,
	"node_created": 0,
	"plaque_labels": 0,
	"floor_plate": 0,
	"floor_plate_approx": 0,
}


## Build the repair node under `parent`. `loader` is the live level_loader
## (group "level_loader") so the authored mesh/material DB is reused.
## `parts` is the diagnostic subset (bulbs/node/plaques/plate); empty = all.
static func build(parent: Node3D, loader: Node, parts: Array = []) -> Node3D:
	if parent == null:
		return null
	var selected: Array = parts.duplicate()
	if selected.is_empty():
		selected = ["bulbs", "node", "plaques", "plate"]
	var script := load("res://src/core/foyer_dressing.gd") as GDScript
	if script == null:
		return null
	var dressing: Node3D = script.new()
	dressing.name = "P1FoyerDressing"
	parent.add_child(dressing)
	if selected.has("bulbs"):
		dressing.call("_repair_emitter_bulbs", parent)
	if selected.has("node"):
		dressing.call("_repair_cyan_node", parent, loader)
	if selected.has("plaques"):
		dressing.call("_add_plaque_text", parent)
	if selected.has("plate"):
		dressing.call("_add_floor_plate", parent, loader)
	return dressing


func _repair_emitter_bulbs(root: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = BULB_EMISSIVE * BULB_BRIGHTNESS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Every emitter bulb in the loaded scene, not only the first 32 m chunk:
	# the 134 Guildhall detectors are split over several MultiMesh items.
	var items: Array[GeometryInstance3D] = []
	_collect_ue_items(root, BULB_SUFFIX, items)
	for item: GeometryInstance3D in items:
		item.material_override = mat
		item.set_meta("p1_bulb_material", true)
	stats["emitter_bulbs"] = items.size()


func _repair_cyan_node(root: Node, loader: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = NODE_LIGHT_COLOR * 3.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var item := _find_ue_item(root, NODE_MESH_SUFFIX, NODE_POS, 1.0)
	# The POI record for this shape is hidden_in_game: the shipped node is a
	# Blueprint/Niagara overlay on top of the authored emissive-shape proxy.
	# Never treat the hidden proxy as the visual (that would leave KF27#3 with
	# no visible node); override a visible item when one exists, otherwise
	# create the visible stand-in below.
	if item != null and item.visible:
		item.material_override = mat
		item.set_meta("p1_cyan_node", true)
		stats["node_items"] = 1
		return
	# Merged/batched runs can fold the authored emissive shape away; keep the
	# node present from the authored mesh rather than dropping KF27#3.
	if loader == null:
		return
	var mesh: Mesh = _loader_mesh(loader, NODE_UE)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "P1CyanNode"
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(Basis.IDENTITY.scaled(NODE_VISUAL_SCALE), NODE_VISUAL_POS)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("p1_cyan_node", true)
	mi.set_meta("placement", "PORT_APPROX (KF27 visual size; POI proxy is hidden_in_game)")
	add_child(mi)
	stats["node_created"] = 1


func _add_plaque_text(root: Node) -> void:
	for rec_v: Variant in PLAQUES:
		var rec: Dictionary = rec_v as Dictionary
		var key: String = str(rec.get("key", ""))
		if not PLAQUE_TEXT.has(key):
			continue
		var b: Array = rec.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]) as Array
		var basis := Basis(
			Vector3(float(b[0]), float(b[3]), float(b[6])),
			Vector3(float(b[1]), float(b[4]), float(b[7])),
			Vector3(float(b[2]), float(b[5]), float(b[8]))
		).orthonormalized()
		# Text3D attaches at (0, 3, 0) cm on the plate; lift it 2 cm off the
		# face so it is not z-fighting the wooden plate.
		var pos: Vector3 = (rec.get("pos", Vector3.ZERO) as Vector3) \
			+ basis.y * 0.03 + basis.z * 0.02
		var label := Label3D.new()
		label.name = "P1Plaque_%s" % key
		label.text = str(PLAQUE_TEXT[key])
		label.font_size = 48
		label.pixel_size = 0.006
		label.outline_size = 10
		label.outline_modulate = Color(0.05, 0.04, 0.03, 0.9)
		label.modulate = Color(0.93, 0.85, 0.64)
		label.shaded = false
		label.double_sided = true
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = false
		label.transform = Transform3D(basis, pos)
		label.set_meta("p1_plaque_text", str(PLAQUE_TEXT[key]))
		label.set_meta("p1_authored_plate", key)
		add_child(label)
		stats["plaque_labels"] = int(stats["plaque_labels"]) + 1


func _add_floor_plate(root: Node, loader: Node) -> void:
	if loader == null:
		return
	var mesh: Mesh = _loader_mesh(loader, FLOOR_PLATE_UE)
	if mesh == null:
		return
	var slots: Array = []
	var db_v: Variant = loader.get("_mesh_mats_db")
	if db_v is Dictionary:
		var sv: Variant = (db_v as Dictionary).get(FLOOR_PLATE_UE, null)
		if sv is Array:
			slots = sv as Array
	var mat: Material = null
	if not slots.is_empty():
		mat = loader.call("get_material_for_ue", str(slots[0])) as Material
	var mi := MeshInstance3D.new()
	mi.name = "P1FloorPlate"
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	# SM_FloorPlate's pivot is a corner (local X -2..0, Z 0..2), so offset by
	# the scaled half extents to centre it on the authored foyer line.
	var s: float = FLOOR_PLATE_SCALE
	mi.transform = Transform3D(
		Basis.IDENTITY.scaled(Vector3(s, s, s)),
		FLOOR_PLATE_POS + Vector3(1.0 * s, 0.0, -1.0 * s))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("p1_floor_plate", true)
	mi.set_meta("placement", "PORT_APPROX (KF27, no authored POI record)")
	add_child(mi)
	stats["floor_plate"] = 1
	stats["floor_plate_approx"] = 1


static func _loader_mesh(loader: Node, ue_path: String) -> Mesh:
	var info_v: Variant = loader.call("_get_mesh_and_shape", ue_path)
	if not (info_v is Dictionary):
		return null
	var mesh_v: Variant = (info_v as Dictionary).get("mesh", null)
	return mesh_v as Mesh if mesh_v is Mesh else null


## First GeometryInstance3D under `root` whose authored UE mesh path ends with
## `suffix`. MultiMesh input items carry the same meta as per-instance ones.
## A negative `radius` accepts any placement; otherwise one instance origin
## must be within `radius` of `target` (so the foyer node is not confused with
## the other SM_Sphere2Count light modules in the POI).
static func _find_ue_item(root: Node, suffix: String, target: Vector3, radius: float) -> GeometryInstance3D:
	if root == null:
		return null
	for child: Node in root.get_children():
		if child is GeometryInstance3D:
			var mp: String = str(child.get_meta("ue_mesh", ""))
			if mp.ends_with(suffix) and (radius < 0.0 or _item_near(child as GeometryInstance3D, target, radius)):
				return child as GeometryInstance3D
		var found: GeometryInstance3D = _find_ue_item(child, suffix, target, radius)
		if found != null:
			return found
	return null


## Every GeometryInstance3D under `root` whose authored UE mesh path ends with
## `suffix` (all chunked MultiMesh items of one mesh, e.g. all emitter bulbs).
static func _collect_ue_items(root: Node, suffix: String, out: Array[GeometryInstance3D]) -> void:
	if root == null:
		return
	for child: Node in root.get_children():
		if child is GeometryInstance3D:
			if str(child.get_meta("ue_mesh", "")).ends_with(suffix):
				out.append(child as GeometryInstance3D)
		_collect_ue_items(child, suffix, out)


static func _item_near(item: GeometryInstance3D, target: Vector3, radius: float) -> bool:
	var mmi := item as MultiMeshInstance3D
	if mmi != null and mmi.multimesh != null:
		var count: int = mmi.multimesh.instance_count
		for i: int in range(count):
			var tr: Transform3D = mmi.multimesh.get_instance_transform(i)
			if (mmi.global_transform * tr).origin.distance_to(target) <= radius:
				return true
		return false
	return item.global_position.distance_to(target) <= radius
