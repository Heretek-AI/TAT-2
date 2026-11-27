extends Node3D
## P1-SAFE: Contract-02 safe-room dressing (S12 / KF14). Builds the three
## subjects the reference frame shows and that the port was missing, from
## authored assets only:
##
##   1. `SafeRoomPortalOutline` - the escape-portal wall outline. Reuses
##      `escape_gate.gd::make_portal_visual()`, i.e. the exact visual the
##      endgame BP_EscapePoint gates use, with the authored BP_EscapePoint
##      size/OpenColor/ClosedColor. It is a visual marker here (the safe-room
##      doorway), not a second extraction system: no Area3D, no
##      `escape_points` group, no change to the 14 authored endgame markers.
##   2. `SafeRoomLanternStation` - `toggleable_lantern.gd`, the ported
##      BP_ToggleableLanternA (`[F] TURN ON` / `[F] TURN OFF`).
##   3. `SafeRoomSpiderFlyer` - `SM_PosterWantedA` + `MI_PosterWanted`. That
##      mesh's authored UV window (U 0..0.324, V 0..0.451) is the top-left cell
##      of `T_PosterWanted_DA.png`, the `WANTED GBP10000 FOR THE CAPTURE
##      "SPIDER"` panel; the other four cells are SM_PosterWantedB..E.
##
## Dressing already authored in `Guildhall_PeripheryA` (not spawned here, but
## the probe pins it): the dark brick wall (`SM_Urban_Ext_Wall_4x6` +
## `MI_Urban_Ext_Stone`, `T_WallStoneBlockD`) and the oval sconce
## (`SM_WallLightB` + `MI_LightsSetA` at 126.29, 27.14, -2.28). The briefing
## backdrop (KF13) is the live safe-room view, not a separate asset.
##
## PLACEMENT IS A PORT_DECISION. The extract authors no BP_EscapePoint and no
## BP_ToggleableLanternA instance in this room: the 14 Guildhall escape markers
## sit in the vault/basement (nearest 44.47, 28.03, -53.54) and the four
## PeripheryA lanterns sit at x 55.22 / 54.79 / -24.80 / -13.02. The three
## props are therefore anchored to authored landmarks - the sconce's wall face
## (z=-2.28), the Contract-02 spawn pose (127.27, 25.47, -5.33) and the floor
## top (25.0) - keeping the KF14 arrangement: brick wall, portal centred, lamp
## and flyer to its left at eye height. The meshes, materials, colours, light
## values and prompts are authored 1:1.

const EscapeScript: GDScript = preload("res://src/interact/escape_gate.gd")
const ToggleableLanternScript: GDScript = preload("res://src/interact/toggleable_lantern.gd")

const POSTER_UE_MESH: String = "/Game/Art/Environment/Props/Posters/SM_PosterWantedA"
const POSTER_UE_MATERIAL: String = "/Game/Art/Environment/Props/Posters/MI_PosterWanted"

## Authored landmark: the oval sconce mount on the brick wall, at floor level.
## SM_WallLightB is authored at (126.29, 27.14, -2.28); the floor
## (GB_Floor_6x6, top 25.0) sets the base.
const WALL_ANCHOR: Vector3 = Vector3(126.29, 25.0, -2.28)

## Local offsets from WALL_ANCHOR (identity basis; +Z is into the wall, -Z is
## the room). The portal is 1.69 m west of the sconce and centred on its own
## authored 2.3868 m height; the lamp sits 0.6 m east at 1.6 m; the flyer sits
## 1.1 m east at 1.5 m. 1-3 cm proud of the wall face avoids z-fighting.
const PORTAL_OFFSET: Vector3 = Vector3(-1.69, 0.0, -0.01)
const LANTERN_OFFSET: Vector3 = Vector3(0.6, 1.6, -0.005)
const FLYER_OFFSET: Vector3 = Vector3(1.1, 1.5, -0.01)

var level_loader: Node = null
var portal: MeshInstance3D = null
var lantern: Node3D = null
var flyer: MeshInstance3D = null
var missing_meshes: int = 0
var missing_materials: int = 0


func _ready() -> void:
	if portal != null:
		return
	_build()


func _build() -> void:
	position = WALL_ANCHOR
	name = "SafeRoomDressing"

	# 1. Portal wall outline (same visual the endgame gates use).
	portal = EscapeScript.make_portal_visual()
	portal.name = "SafeRoomPortalOutline"
	# make_portal_visual() centres the quad so its bottom sits on the gate
	# origin; keep that offset and put the origin on the authored floor line.
	portal.position = PORTAL_OFFSET + Vector3(0.0, EscapeScript.PORTAL_SIZE.y * 0.5, 0.0)
	# QuadMesh faces +Z; the room is at -Z, so turn the outline to face it.
	portal.rotation.y = PI
	add_child(portal)

	# 2. Caged lantern station (authored BP_ToggleableLanternA port).
	lantern = ToggleableLanternScript.new() as Node3D
	lantern.name = "SafeRoomLanternStation"
	lantern.position = LANTERN_OFFSET
	lantern.set("level_loader", level_loader)
	add_child(lantern)

	# 3. "SPIDER" flyer, pinned flat on the brick beside the lamp.
	flyer = _poster_mesh()
	if flyer != null:
		flyer.name = "SafeRoomSpiderFlyer"
		flyer.position = FLYER_OFFSET
		flyer.rotation.y = PI
		add_child(flyer)


func _poster_mesh() -> MeshInstance3D:
	if level_loader == null or not level_loader.has_method("_get_mesh_and_shape"):
		missing_meshes += 1
		return null
	var info: Dictionary = level_loader.call("_get_mesh_and_shape", POSTER_UE_MESH) as Dictionary
	var mesh: Mesh = info.get("mesh") as Mesh
	if mesh == null:
		missing_meshes += 1
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_meta("ue_mesh", POSTER_UE_MESH)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: Material = null
	if level_loader.has_method("get_material_for_ue"):
		mat = level_loader.call("get_material_for_ue", POSTER_UE_MATERIAL) as Material
	if mat == null:
		missing_materials += 1
	else:
		for s: int in range(mesh.get_surface_count()):
			mi.set_surface_override_material(s, mat)
	return mi


## QA helper: the authored fan-out of this dressing, printed once per load.
func report() -> String:
	return "P1-SAFE dressing: anchor=%s portal=%s lantern=%s flyer=%s missing_meshes=%d missing_materials=%d" % [
		str(WALL_ANCHOR),
		"portal" if portal != null else "MISSING",
		"lantern" if lantern != null else "MISSING",
		"spider_flyer" if flyer != null else "MISSING",
		missing_meshes,
		missing_materials,
	]
