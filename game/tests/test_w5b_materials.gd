extends SceneTree
## W5B material-truth test: masked opacity, skybox mountain substitution and
## the DiffuseMaskTint switch (static/headless, real materials.json).
##
## 1. Masked opacity. Godot's alpha scissor only reads the albedo texture's
##    alpha, but UE masked masters can keep the silhouette in a separate
##    Opacity map. MI_HorizonA (the 558 x 140 m horizon card) is
##    BLEND_Masked with its skyline in T_HorizonA_BCO.png, yet it bound
##    T_TrimMetalB_DA, whose alpha is 255 everywhere: the card rendered as one
##    solid black wall. The loader now composes the authored mask into the
##    albedo alpha (or uses the _BCO map verbatim, RGB = base colour, A = mask).
##    This test proves the mask, not the albedo alpha, decides the cut-out.
## 2. Skybox mountains. SkyboxGeo binds the WorldGridMaterial placeholder on
##    SM_Mountain02/07/16/18_Grass, so the horizon was the grey checkerboard.
##    The substitution is scoped to /skybox/mountains/ + "sm_mountain" stems;
##    the sphere and the bay-window roof keep their WorldGrid surface.
## 3. DiffuseMaskTint. Every M_Env* instance inherits the master's
##    [0.5331,0.5645,0.6979] vector while `DiffuseColorMask?` is off (0 of the
##    generated materials have it on), so the tint must never be applied
##    unconditionally; when it is on, the authored linear value is converted to
##    sRGB exactly once.
##
## Run:
##   XDG_DATA_HOME=... tools/godot --headless --path game \
##     --script res://tests/test_w5b_materials.gd

const LOADER_PATH := "res://src/core/level_loader.gd"
const MAT_DB := "res://data/generated/materials.json"

const HORIZON_MI := "/Game/Art/Environment/Skybox/Buildings/MI_HorizonA"
const HORIZON_MASK := "res://assets/ue/Raw/Art/Environment/Skybox/Buildings/T_HorizonA_BCO.png"
const HORIZON_WRONG_ALBEDO := "res://assets/ue/Raw/MaterialLibrary/Environment/Metal/T_TrimMetalB_DA.png"
const SLIME_MI := "/Game/Art/Effects/MagicSlime/MI_MagicSlime_Bubble"
const POSTER_MI := "/Game/Art/Environment/Props/Posters/MI_PosterWanted"
const POSTER_ALBEDO := "res://assets/ue/Raw/Art/Environment/Props/Posters/T_PosterWanted_DA.png"
const POSTER_MASK_TINT: Array[float] = [0.5331, 0.5645, 0.6979]
const MOUNTAIN_MESH := "/Game/Art/Environment/Skybox/Mountains/SM_Mountain02_Grass"
const MOUNTAIN_ALBEDO := "T_Mountain_16_Grass_BaseColor.png"
const SPHERE_MESH := "/Game/Art/Environment/Utilities/SM_Sphere_100cm"
const BAY_ROOF_MESH := "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_BayWindowA_6x8"

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
	check_masked_opacity()
	check_mountain_substitution()
	check_poster_tint()
	ll.free()
	print("W5B_MATERIAL_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


## Fraction of texels whose alpha is below 0.5 (a real cut-out mask).
func _alpha_cutout_fraction(tex: Texture2D) -> float:
	if tex == null:
		return -1.0
	var img: Image = tex.get_image()
	if img == null:
		return -1.0
	img = (img.duplicate() as Image)
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var d: PackedByteArray = img.get_data()
	if d.is_empty():
		return -1.0
	var below: int = 0
	var i: int = 3
	while i < d.size():
		if d[i] < 128:
			below += 1
		i += 4
	return float(below) / float(d.size() / 4)


func check_masked_opacity() -> void:
	var mat: Material = ll.call("get_material_for_ue", HORIZON_MI)
	_check(mat is StandardMaterial3D, "MI_HorizonA builds a StandardMaterial3D",
		"MI_HorizonA did not build a StandardMaterial3D")
	if not (mat is StandardMaterial3D):
		return
	var sm := mat as StandardMaterial3D
	_check(sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
		"MI_HorizonA stays masked (alpha scissor %.4f)" % sm.alpha_scissor_threshold,
		"MI_HorizonA lost its masked blend (transparency=%d)" % sm.transparency)
	_check(sm.albedo_texture != null and sm.albedo_texture.resource_path == HORIZON_MASK,
		"MI_HorizonA albedo is the authored BCO card (base colour + opacity)",
		"MI_HorizonA albedo is %s (expected %s)" % [
			sm.albedo_texture.resource_path if sm.albedo_texture != null else "null", HORIZON_MASK])
	_check(str(sm.get_meta("masked_opacity", "")) == HORIZON_MASK,
		"MI_HorizonA records the bound opacity mask",
		"MI_HorizonA masked_opacity meta is %s" % str(sm.get_meta("masked_opacity", "")))
	var mask_cut: float = _alpha_cutout_fraction(sm.albedo_texture)
	_check(mask_cut > 0.10,
		"MI_HorizonA bound alpha is a real skyline (%.1f %% of texels masked out)" % (mask_cut * 100.0),
		"MI_HorizonA bound alpha has no cut-out (%.3f below 0.5)" % mask_cut)
	# Negative control: the albedo it used to bind carries no alpha at all, so
	# using albedo alpha as the mask was never going to cut anything out.
	var old_alb: Texture2D = ll.call("_load_tex", HORIZON_WRONG_ALBEDO) as Texture2D
	var old_cut: float = _alpha_cutout_fraction(old_alb)
	_check(old_cut >= 0.0 and old_cut < 0.001,
		"control: the old metal albedo has no alpha cut-out (%.3f below 0.5)" % old_cut,
		"control failed: old albedo alpha cuts out %.3f of texels" % old_cut)
	# A grayscale _O map (mask in R, alpha 255) must be composed, not ignored.
	var smat: Material = ll.call("get_material_for_ue", SLIME_MI)
	if smat is StandardMaterial3D:
		var s2 := smat as StandardMaterial3D
		var composed_cut: float = _alpha_cutout_fraction(s2.albedo_texture)
		_check(str(s2.get_meta("masked_opacity", "")) != "",
			"MI_MagicSlime_Bubble binds its authored grayscale mask",
			"MI_MagicSlime_Bubble did not bind a masked opacity map")
		_check(composed_cut > 0.05,
			"MI_MagicSlime_Bubble composed alpha carries the bubble mask (%.1f %% masked)" % (composed_cut * 100.0),
			"MI_MagicSlime_Bubble composed alpha has no cut-out (%.3f)" % composed_cut)
	else:
		_check(false, "MI_MagicSlime_Bubble builds a StandardMaterial3D", "MI_MagicSlime_Bubble not standard")
	# A masked material with no texs.opacity must keep its own albedo alpha.
	var pmat: Material = ll.call("get_material_for_ue", POSTER_MI)
	if pmat is StandardMaterial3D:
		var p2 := pmat as StandardMaterial3D
		_check(str(p2.get_meta("masked_opacity", "")) == "",
			"control: MI_PosterWanted (no opacity map) keeps its albedo alpha",
			"control: MI_PosterWanted grew a masked opacity binding")


func _surface_albedo_paths(mesh: Mesh) -> Array[String]:
	var out: Array[String] = []
	for s: int in range(mesh.get_surface_count()):
		var m: Material = mesh.surface_get_material(s)
		if m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture != null:
			out.append((m as StandardMaterial3D).albedo_texture.resource_path.get_file())
		else:
			out.append("")
	return out


func check_mountain_substitution() -> void:
	_check(bool(ll.call("_is_skybox_mountain_mesh", MOUNTAIN_MESH.to_lower())),
		"SM_Mountain02_Grass is in the mountain scope", "mountain scope missed SM_Mountain02_Grass")
	_check(not bool(ll.call("_is_skybox_mountain_mesh", BAY_ROOF_MESH.to_lower())),
		"control: a /roofs/ mesh is outside the mountain scope", "mountain scope leaked into roofs")
	_check(not bool(ll.call("_is_skybox_mountain_mesh", "/game/art/environment/skybox/buildings/sm_mountain02_grass")),
		"control: an sm_mountain stem outside /skybox/mountains/ is not substituted",
		"mountain scope ignores the directory")
	var minfo: Dictionary = ll.call("_get_mesh_and_shape", MOUNTAIN_MESH)
	var mmesh: Mesh = minfo.get("mesh") as Mesh
	_check(mmesh != null, "SM_Mountain02_Grass loads", "cannot load SM_Mountain02_Grass")
	if mmesh != null:
		var paths: Array[String] = _surface_albedo_paths(mmesh)
		var all_mountain: bool = not paths.is_empty()
		for p: String in paths:
			if p != MOUNTAIN_ALBEDO:
				all_mountain = false
		_check(all_mountain,
			"SM_Mountain02_Grass WorldGrid -> MI_Mountain17 (%s)" % MOUNTAIN_ALBEDO,
			"SM_Mountain02_Grass surfaces are %s (expected only %s)" % [str(paths), MOUNTAIN_ALBEDO])
		var any_grid: bool = false
		for s: int in range(mmesh.get_surface_count()):
			if bool(ll.call("_is_worldgrid_material", mmesh.surface_get_material(s))):
				any_grid = true
		_check(not any_grid, "SM_Mountain02_Grass has no WorldGrid surface left",
			"SM_Mountain02_Grass still shows the WorldGrid placeholder")
	# Negative controls: the placeholder stays where it is authored.
	for rec: Dictionary in [
		{"path": SPHERE_MESH, "label": "SM_Sphere_100cm"},
		{"path": BAY_ROOF_MESH, "label": "SM_RoofUrbanB_Ext_BayWindowA_6x8"},
	]:
		var mp: String = str(rec["path"])
		var info: Dictionary = ll.call("_get_mesh_and_shape", mp)
		var mesh: Mesh = info.get("mesh") as Mesh
		if mesh == null:
			_check(false, "control mesh %s loads" % str(rec["label"]), "cannot load " + mp)
			continue
		var grid_surfaces: int = 0
		for s: int in range(mesh.get_surface_count()):
			if bool(ll.call("_is_worldgrid_material", mesh.surface_get_material(s))):
				grid_surfaces += 1
		_check(grid_surfaces > 0,
			"control: %s keeps its intentional WorldGrid surface (%d)" % [str(rec["label"]), grid_surfaces],
			"control: %s lost its WorldGrid surface (substitution not name-scoped)" % str(rec["label"]))


func check_poster_tint() -> void:
	# Material dump: the WANTED poster keeps the authored sepia albedo, untinted.
	var mat: Material = ll.call("get_material_for_ue", POSTER_MI)
	_check(mat is StandardMaterial3D, "MI_PosterWanted builds a StandardMaterial3D",
		"MI_PosterWanted did not build a StandardMaterial3D")
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		_check(sm.albedo_texture != null and sm.albedo_texture.resource_path == POSTER_ALBEDO,
			"MI_PosterWanted binds its authored albedo (%s)" % POSTER_ALBEDO.get_file(),
			"MI_PosterWanted albedo is %s" % (sm.albedo_texture.resource_path if sm.albedo_texture else "null"))
		_check(sm.albedo_color.is_equal_approx(Color(1.0, 1.0, 1.0, 1.0)),
			"MI_PosterWanted albedo tint is untouched white (sepia poster stays sepia)",
			"MI_PosterWanted albedo tint is %s (DiffuseMaskTint leaked while its switch is off)" % str(sm.albedo_color))
		_check(sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(sm.alpha_scissor_threshold, 0.3333),
			"MI_PosterWanted is masked at the authored clip 0.3333",
			"MI_PosterWanted mask clip is wrong (transparency=%d clip=%.4f)" % [sm.transparency, sm.alpha_scissor_threshold])
		_check(sm.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"MI_PosterWanted keeps two-sided (authored)", "MI_PosterWanted lost its two-sided flag")
	# The authored vector exists in the DB and the switch is off for every MI.
	var db_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAT_DB))
	var switch_on: int = 0
	var vector_rows: int = 0
	if db_v is Dictionary:
		for key_v: Variant in (db_v as Dictionary).keys():
			var info: Dictionary = (db_v as Dictionary)[key_v]
			if not (info is Dictionary):
				continue
			var switches: Dictionary = (info as Dictionary).get("switches", {})
			for sk: Variant in switches.keys():
				if str(sk).to_lower().replace("?", "") == "diffusecolormask" and switches[sk] == true:
					switch_on += 1
			var vectors: Dictionary = (info as Dictionary).get("vectors", {})
			if vectors.has("DiffuseMaskTint"):
				vector_rows += 1
	_check(vector_rows > 0, "materials.json carries DiffuseMaskTint on %d materials" % vector_rows,
		"materials.json lost the DiffuseMaskTint rows (producer drift)")
	_check(switch_on == 0, "DiffuseColorMask? is off on every generated material",
		"%d materials have DiffuseColorMask? on; re-measure the poster tint" % switch_on)
	# The gate itself: off -> untouched, on -> linear_to_srgb converted once.
	var off_info: Dictionary = {
		"switches": {"DiffuseColorMask?": false},
		"vectors": {"DiffuseMaskTint": [POSTER_MASK_TINT[0], POSTER_MASK_TINT[1], POSTER_MASK_TINT[2], 1.0]},
	}
	var off_mat := StandardMaterial3D.new()
	ll.call("_apply_diffuse_mask_tint", off_mat, off_info)
	_check(off_mat.albedo_color.is_equal_approx(Color(1.0, 1.0, 1.0, 1.0)),
		"switch off: DiffuseMaskTint is not applied", "switch off applied the tint: %s" % str(off_mat.albedo_color))
	var on_info: Dictionary = {
		"switches": {"DiffuseColorMask?": true},
		"vectors": {"DiffuseMaskTint": [POSTER_MASK_TINT[0], POSTER_MASK_TINT[1], POSTER_MASK_TINT[2], 1.0]},
	}
	var on_mat := StandardMaterial3D.new()
	ll.call("_apply_diffuse_mask_tint", on_mat, on_info)
	var want: Color = Color(POSTER_MASK_TINT[0], POSTER_MASK_TINT[1], POSTER_MASK_TINT[2]).linear_to_srgb()
	_check(on_mat.albedo_color.is_equal_approx(want),
		"switch on: tint is linear_to_srgb(%s) once" % str(want),
		"switch on tint is %s (expected %s)" % [str(on_mat.albedo_color), str(want)])
	_check(absf(on_mat.albedo_color.r - POSTER_MASK_TINT[0]) > 0.05,
		"switch on: the tint is not the raw linear value (%.3f vs %.3f)" % [on_mat.albedo_color.r, POSTER_MASK_TINT[0]],
		"switch on tint equals the raw linear value (no sRGB conversion)")
