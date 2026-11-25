extends SceneTree
## W6L searchlight material truth (static/headless, real shipped assets).
##
## VFX_SkySearchLight_Mesh is the authored sky searchlight cone under
## /Game/Art/Environment/Lights/Searchlight/. It binds the engine placeholder
## WorldGridMaterial (like the skybox mountains did before W5B), so the cone
## rendered as the grey UE checkerboard instead of a light shaft. The loader's
## additive light-shaft path only matched "lightshaft"/"godray" names.
##
## The fix adds a *scoped* token: `skysearchlight` by name, or `searchlight`
## only on a VFX_ / /vfx/ asset. The hard-surface fixtures in the same folder
## (SM_Searchlight, SM_SearchlightBase, SM_SearchlightLensSmall,
## SM_SearchlightSwivelSmall) must keep their authored MI_Searchlight materials,
## and WorldGrid must stay intentional everywhere else (SM_Sphere_100cm).
##
## Run:
##   XDG_DATA_HOME=... tools/godot --headless --path game \
##     --script res://tests/test_w6l_searchlight.gd

const LOADER_PATH := "res://src/core/level_loader.gd"
const SHAFT_MESH := "/Game/Art/Environment/Lights/Searchlight/VFX_SkySearchLight_Mesh"
const FIXTURES: Array[String] = [
	"/Game/Art/Environment/Lights/Searchlight/SM_Searchlight",
	"/Game/Art/Environment/Lights/Searchlight/SM_SearchlightBase",
	"/Game/Art/Environment/Lights/Searchlight/SM_SearchlightLensSmall",
	"/Game/Art/Environment/Lights/Searchlight/SM_SearchlightSwivelSmall",
]
const SPHERE_MESH := "/Game/Art/Environment/Utilities/SM_Sphere_100cm"

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
	ll.call("_load_material_dbs")
	check_scope()
	check_shaft_material()
	check_fixture_controls()
	ll.free()
	print("W6L_SEARCHLIGHT_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


## Only the VFX cone is a shaft; the fixtures share the folder name.
func check_scope() -> void:
	_check(bool(ll.call("_is_additive_light_shaft", SHAFT_MESH.to_lower())),
		"VFX_SkySearchLight_Mesh is in the additive light-shaft scope",
		"VFX_SkySearchLight_Mesh is outside the light-shaft scope")
	for fixture: String in FIXTURES:
		_check(not bool(ll.call("_is_additive_light_shaft", fixture.to_lower())),
			"control: %s is not a light shaft" % fixture.get_file(),
			"control: %s was routed to the additive shaft path" % fixture.get_file())
	_check(bool(ll.call("_is_additive_light_shaft", "/Game/Art/VFX/LightShaft/SM_LightShaft_Gothic".to_lower())),
		"legacy lightshaft names still route to the shaft path",
		"lightshaft routing regressed")
	_check(bool(ll.call("_is_additive_light_shaft", "/Game/Art/VFX/GodRay/SM_GodRay_A".to_lower())),
		"legacy godray names still route to the shaft path",
		"godray routing regressed")


## The authored cone leaves WorldGrid and gets the unshaded additive card.
func check_shaft_material() -> void:
	var info: Dictionary = ll.call("_get_mesh_and_shape", SHAFT_MESH)
	var mesh: Mesh = info.get("mesh") as Mesh
	_check(mesh != null, "VFX_SkySearchLight_Mesh loads", "cannot load VFX_SkySearchLight_Mesh")
	if mesh == null:
		return
	var grid_surfaces: int = 0
	var beam_surfaces: int = 0
	var bad_mat: Array[String] = []
	for s: int in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(s)
		if bool(ll.call("_is_worldgrid_material", mat)):
			grid_surfaces += 1
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			var is_beam: bool = sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
				and sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
				and sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD \
				and sm.cull_mode == BaseMaterial3D.CULL_DISABLED \
				and sm.albedo_color.a <= 0.20
			if is_beam:
				beam_surfaces += 1
			else:
				bad_mat.append("%s %s" % [sm.get_class(), str(sm.albedo_color)])
		else:
			bad_mat.append("null" if mat == null else mat.get_class())
	_check(grid_surfaces == 0,
		"VFX_SkySearchLight_Mesh has no WorldGrid surface left (%d surfaces)" % mesh.get_surface_count(),
		"VFX_SkySearchLight_Mesh still shows WorldGrid on %d surfaces" % grid_surfaces)
	_check(beam_surfaces == mesh.get_surface_count(),
		"all %d cone surfaces use the authored additive unshaded card" % beam_surfaces,
		"shaft surfaces not on the additive card: " + str(bad_mat))


## Fixtures keep authored materials; WorldGrid stays where it is intentional.
func check_fixture_controls() -> void:
	for fixture: String in FIXTURES:
		var info: Dictionary = ll.call("_get_mesh_and_shape", fixture)
		var mesh: Mesh = info.get("mesh") as Mesh
		if mesh == null:
			_check(false, "fixture %s loads" % fixture.get_file(), "cannot load " + fixture)
			continue
		var beam_surfaces: int = 0
		for s: int in range(mesh.get_surface_count()):
			var mat: Material = mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				if sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
					beam_surfaces += 1
		_check(beam_surfaces == 0,
			"fixture %s keeps its authored (lit, opaque) material" % fixture.get_file(),
			"fixture %s took the additive shaft override" % fixture.get_file())
	var sphere_info: Dictionary = ll.call("_get_mesh_and_shape", SPHERE_MESH)
	var sphere_mesh: Mesh = sphere_info.get("mesh") as Mesh
	_check(sphere_mesh != null, "control: SM_Sphere_100cm loads", "cannot load SM_Sphere_100cm")
	if sphere_mesh != null:
		var grid: int = 0
		for s: int in range(sphere_mesh.get_surface_count()):
			if bool(ll.call("_is_worldgrid_material", sphere_mesh.surface_get_material(s))):
				grid += 1
		_check(grid > 0,
			"control: SM_Sphere_100cm keeps its intentional WorldGrid (%d surface)" % grid,
			"control: WorldGrid was hidden globally (sphere lost its surface)")
