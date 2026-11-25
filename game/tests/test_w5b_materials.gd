extends SceneTree
## W5B/W6L material-truth test: masked opacity, skybox mountain substitution,
## the DiffuseMaskTint switch, and the W6L metallic/roughness/emissive/backlight
## mapping.
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
## 4. W6L metallic precedence. `Metallic Map?`/`Use Metallic Map` + ORM means
##    the map drives (metallic 1.0); FlatMetallic is only the map-off fallback.
##    584 generated materials were rendering as dielectrics because the
##    authored FlatMetallic 0.0 won over the authored map.
## 5. W6L roughness range. Godot multiplies the scalar by the ORM green
##    channel, so the old (low+high)/2 midpoint halved every authored value.
##    The range is now low + g*(high-low), baked once per (ORM, range) into an
##    L8 map (brass 0.15..1.0 -> mean 0.41, paper 0..1 -> 0.70) and never the
##    average.
## 6. W6L two-tone emissive. EmissiveTintA/B resolves to the lit end and each
##    family has an energy ceiling (glass 3.0, guard lantern 1.6, large lamps
##    2.5), so the authored 50-100x strengths no longer clip pure white;
##    MI_LightSmGlassA_Gold keeps its exact authored 2.2 x EmissiveTintB.
## 7. W6L Den pane. A mask IS the opacity: mask-based glass caps opacity_scale
##    at 1.0, so the centre transmission is the thin-glass floor (~0.21 at mask
##    0.51) instead of saturating, while the fresnel rim stays.
## 8. W6L foliage gate. MSM_Subsurface alone is not foliage: WANTED posters,
##    decals, coins and scrolls inherit it, so backlight is gated on authored
##    foliage tokens/TwoSidedFoliage and those flat cards stay off.
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

## W6L material pins (measured on the shipped materials.json).
const PHONOGRAPH_MI := "/Game/Art/Environment/Props/Musical/Phonograph/ML/MI_Phonograph"
const BRASS_MI := "/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalA_brass"
const MAP_MI := "/Game/Art/Environment/ThievesDen/Stations/MI_Map_ThievesDen"
const METALLIC_MAP_ON_COUNT: int = 584
const BRASS_ROUGHNESS_MEAN: float = 0.408
const PAPER_ROUGHNESS_MEAN: float = 0.703
const GOLD_LAMP_MI := "/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Gold"
const BLUE_LAMP_MI := "/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Blue"
const GUARD_LANTERN_MI := "/Game/Art/Environment/Lights/Mobile/MI_LanternGuardGlass_Yellow"
const LARGE_LAMP_MI := "/Game/Art/Environment/Lights/LightModules/MI_LightLrgABC_Glass_Orange"
const GLASS_LIGHT_MI := "/Game/MaterialLibrary/Environment/Glass/Opaque/MI_GlassLight_Gold"
const DEN_PANE_OLD := "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_oldmanor"
const DEN_PANE := "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels"
const GLASS_CAP: float = 3.0
const GUARD_LANTERN_CAP: float = 1.6
const LARGE_LAMP_CAP: float = 2.5
const EMISSIVE_CEIL: float = 4.0
const PURE_WHITE_MIN: float = 0.99
const DECAL_POSTER_MI := "/Game/Art/Environment/Props/Signage/Decals/Posters/MI_DecalPosters"
const COINS_MI := "/Game/Art/Gameplay/Loot/LootMinor/Coins/MI_Coins"
const POSTER_A_MI := "/Game/Art/Environment/Props/Posters/MI_PosterA"
const BIRCH_LEAVES_MI := "/Game/ThirdParty/Stylized_forest_2/Materials/Trees/UpdatedMaterials/MI_BirchLeaves"
const BIRCH_BARK_MI := "/Game/ThirdParty/Stylized_forest_2/Materials/Trees/UpdatedMaterials/MI_BirchBark"
const PINE_NEEDLES_MI := "/Game/ThirdParty/Stylized_forest_2/Materials/Trees/UpdatedMaterials/MI_ISMPineNeedles"

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
	check_metallic_precedence()
	check_roughness_range()
	check_two_tone_emissive()
	check_emissive_ceiling_audit()
	check_den_pane()
	check_foliage_backlight()
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


func _db() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAT_DB))
	return parsed as Dictionary if parsed is Dictionary else {}


## Mean of the green channel (the ORM roughness channel) of a texture.
func _mean_green(tex: Texture2D) -> float:
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
	var sum: int = 0
	var n: int = 0
	var i: int = 1
	while i < d.size():
		sum += d[i]
		n += 1
		i += 4
	return float(sum) / float(n) / 255.0


## W6L #4: the authored Metallic Map switch drives, FlatMetallic only when off.
func check_metallic_precedence() -> void:
	var phono: Material = ll.call("get_material_for_ue", PHONOGRAPH_MI)
	if phono is StandardMaterial3D:
		var p := phono as StandardMaterial3D
		_check(p.metallic >= 0.5,
			"MI_Phonograph is map-driven metal (metallic %.2f)" % p.metallic,
			"MI_Phonograph metallic %.2f < 0.5 (FlatMetallic 0.0 still wins)" % p.metallic)
		_check(p.metallic_texture != null and p.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE,
			"MI_Phonograph binds the ORM blue channel as the metallic map",
			"MI_Phonograph lost its metallic map binding")
	else:
		_check(false, "MI_Phonograph builds a StandardMaterial3D", "MI_Phonograph not StandardMaterial3D")
	var brass: Material = ll.call("get_material_for_ue", BRASS_MI)
	if brass is StandardMaterial3D:
		var b := brass as StandardMaterial3D
		_check(b.metallic >= 0.8,
			"MI_TrimMetalA_brass is map-driven metal (metallic %.2f)" % b.metallic,
			"MI_TrimMetalA_brass metallic %.2f < 0.8" % b.metallic)
	else:
		_check(false, "MI_TrimMetalA_brass builds a StandardMaterial3D", "brass not StandardMaterial3D")
	var map_mat: Material = ll.call("get_material_for_ue", MAP_MI)
	if map_mat is StandardMaterial3D:
		var m := map_mat as StandardMaterial3D
		_check(is_zero_approx(m.metallic),
			"control: MI_Map_ThievesDen (Metallic Map? off) stays dielectric 0.0",
			"control: MI_Map_ThievesDen metallic %.3f (map-off flat leaked)" % m.metallic)
	else:
		_check(false, "MI_Map_ThievesDen builds a StandardMaterial3D", "map material not StandardMaterial3D")
	# DB-wide: every map-on + ORM entry must resolve to 1.0, and map-off entries
	# must keep their authored flat value.
	var db := _db()
	var on_count: int = 0
	var on_bad: Array[String] = []
	var off_bad: Array[String] = []
	for key_v: Variant in db.keys():
		var info: Dictionary = db[key_v] as Dictionary
		if info.is_empty():
			continue
		var texs: Dictionary = info.get("texs", {})
		if str(texs.get("orm", "")) == "":
			continue
		var norm_params: Dictionary = ll.call("_ue_norm_map", info.get("params", {}))
		var norm_sw: Dictionary = ll.call("_ue_norm_map", info.get("switches", {}))
		var on: bool = ll.call("_ue_lookup", norm_sw, ["metallicmap?", "usemetallicmap"]) == true
		var probe := StandardMaterial3D.new()
		ll.call("_apply_ue_pbr_params", probe, info)
		if on:
			on_count += 1
			if not is_equal_approx(probe.metallic, 1.0):
				on_bad.append("%s (%.3f)" % [str(key_v).get_file(), probe.metallic])
		else:
			var flat_v: Variant = ll.call("_ue_lookup", norm_params, ["metallic", "metalness", "flatmetallic"])
			if flat_v != null and not is_equal_approx(probe.metallic, clampf(float(flat_v), 0.0, 1.0)):
				off_bad.append("%s (%.3f vs %.3f)" % [str(key_v).get_file(), probe.metallic, float(flat_v)])
	_check(on_count == METALLIC_MAP_ON_COUNT,
		"metallic-map-on materials: %d generated (audit count)" % on_count,
		"metallic-map-on count changed: %d (expected %d)" % [on_count, METALLIC_MAP_ON_COUNT])
	_check(on_bad.is_empty(),
		"all %d metallic-map-on materials resolve metallic 1.0 (map drives)" % on_count,
		"map-on materials not driven by the map: " + str(on_bad))
	_check(off_bad.is_empty(),
		"map-off materials keep their authored flat metallic",
		"map-off materials changed: " + str(off_bad))


## W6L #5: roughness is low + g*(high-low), never the retired midpoint.
func check_roughness_range() -> void:
	var brass: Material = ll.call("get_material_for_ue", BRASS_MI)
	if brass is StandardMaterial3D:
		var b := brass as StandardMaterial3D
		var remap_v: Variant = b.get_meta("ue_roughness_remap", null)
		_check(remap_v is Vector2 and is_equal_approx((remap_v as Vector2).x, 0.15) and is_equal_approx((remap_v as Vector2).y, 1.0),
			"brass authors the remap range 0.15..1.0", "brass remap range is %s" % str(remap_v))
		_check(is_equal_approx(b.roughness, 1.0),
			"brass roughness scalar is 1.0 (the remapped map is the value)",
			"brass roughness scalar %.3f (not 1.0)" % b.roughness)
		var mean: float = _mean_green(b.roughness_texture)
		_check(absf(mean - BRASS_ROUGHNESS_MEAN) <= 0.02,
			"brass baked roughness mean %.3f (target %.2f, old midpoint gave 0.17)" % [mean, BRASS_ROUGHNESS_MEAN],
			"brass baked roughness mean %.3f outside %.2f +/- 0.02" % [mean, BRASS_ROUGHNESS_MEAN])
		var img: Image = b.roughness_texture.get_image() if b.roughness_texture != null else null
		_check(img != null and img.get_format() == Image.FORMAT_L8,
			"brass roughness is a single-channel L8 bake (no second RGBA ORM)",
			"brass roughness texture is not L8")
	else:
		_check(false, "brass builds a StandardMaterial3D", "brass not StandardMaterial3D")
	var poster: Material = ll.call("get_material_for_ue", POSTER_MI)
	if poster is StandardMaterial3D:
		var p := poster as StandardMaterial3D
		_check(not p.has_meta("ue_roughness_remap") and is_equal_approx(p.roughness, 1.0),
			"identity range 0..1 binds the ORM directly with scalar 1.0 (no bake)",
			"identity range allocated a remap or kept a midpoint scalar (%.3f)" % p.roughness)
		var mean2: float = _mean_green(p.roughness_texture)
		_check(absf(mean2 - PAPER_ROUGHNESS_MEAN) <= 0.03,
			"paper-range roughness mean %.3f (target %.2f; old midpoint gave 0.35)" % [mean2, PAPER_ROUGHNESS_MEAN],
			"paper roughness mean %.3f outside %.2f +/- 0.03" % [mean2, PAPER_ROUGHNESS_MEAN])
	else:
		_check(false, "paper material builds a StandardMaterial3D", "paper material not StandardMaterial3D")
	# DB-wide: only genuine low<high, non-identity ranges allocate a bake, and
	# no-ORM ranges use the safe high end.
	var db := _db()
	var remaps: int = 0
	var bad: Array[String] = []
	var no_orm_bad: Array[String] = []
	for key_v: Variant in db.keys():
		var info: Dictionary = db[key_v] as Dictionary
		if info.is_empty():
			continue
		var texs: Dictionary = info.get("texs", {})
		var np: Dictionary = ll.call("_ue_norm_map", info.get("params", {}))
		var lo: Variant = ll.call("_ue_lookup", np, ["roughnesslow", "roughnessmin"])
		var hi: Variant = ll.call("_ue_lookup", np, ["roughnesshigh", "roughnessmax"])
		if lo == null or hi == null:
			continue
		var probe := StandardMaterial3D.new()
		ll.call("_apply_ue_pbr_params", probe, info)
		var has_orm: bool = str(texs.get("orm", "")) != ""
		if probe.has_meta("ue_roughness_remap"):
			remaps += 1
			var rv: Vector2 = probe.get_meta("ue_roughness_remap") as Vector2
			# An inverted but non-negative authored range is legal (decreasing
			# ramp); only an identity range would mean the bake is pointless.
			if is_equal_approx(rv.x, rv.y) or (is_zero_approx(rv.x) and is_equal_approx(rv.y, 1.0)):
				bad.append("%s (%s)" % [str(key_v).get_file(), str(rv)])
		var flat_rough: Variant = ll.call("_ue_lookup", np, ["flatroughness"])
		if not has_orm and flat_rough == null and not is_equal_approx(float(lo), float(hi)):
			if not is_equal_approx(probe.roughness, clampf(maxf(float(lo), float(hi)), 0.0, 1.0)):
				no_orm_bad.append("%s (%.3f)" % [str(key_v).get_file(), probe.roughness])
	_check(remaps > 0 and bad.is_empty(),
		"%d materials bake a real authored low/high roughness range" % remaps,
		"invalid roughness bakes: " + str(bad))
	_check(no_orm_bad.is_empty(),
		"no-ORM ranges use the safe high end (never a midpoint)",
		"no-ORM ranges wrong: " + str(no_orm_bad))


## W6L #6: two-tone emissive resolves to the lit tint and the family ceiling.
func check_two_tone_emissive() -> void:
	var gold: Material = ll.call("get_material_for_ue", GOLD_LAMP_MI)
	if gold is StandardMaterial3D:
		var g := gold as StandardMaterial3D
		_check(g.emission_enabled and g.emission.is_equal_approx(Color(1.0, 0.6058, 0.1927, 1.0)),
			"MI_LightSmGlassA_Gold keeps its exact EmissiveTintB (byte-identical)",
			"MI_LightSmGlassA_Gold emission changed: %s" % str(g.emission))
		_check(is_equal_approx(g.emission_energy_multiplier, 2.2),
			"MI_LightSmGlassA_Gold keeps the authored 2.2 multiplier",
			"MI_LightSmGlassA_Gold energy %.3f (expected 2.2)" % g.emission_energy_multiplier)
	else:
		_check(false, "MI_LightSmGlassA_Gold builds a StandardMaterial3D", "gold lamp not StandardMaterial3D")
	for rec: Dictionary in [
		{"path": BLUE_LAMP_MI, "label": "small blue lamp", "tint": Color(0.0723, 0.4125, 1.0), "cap": GLASS_CAP},
		{"path": GLASS_LIGHT_MI, "label": "gold glass light", "tint": Color(1.0, 0.5788, 0.2292), "cap": GLASS_CAP},
		{"path": GUARD_LANTERN_MI, "label": "guard lantern", "tint": Color(1.0, 0.7231, 0.4287), "cap": GUARD_LANTERN_CAP},
		{"path": LARGE_LAMP_MI, "label": "large orange lamp", "tint": Color(0.2, 0.056, 0.0), "cap": LARGE_LAMP_CAP},
	]:
		var mat: Material = ll.call("get_material_for_ue", str(rec["path"]))
		if not (mat is StandardMaterial3D):
			_check(false, "%s builds a StandardMaterial3D" % str(rec["label"]), "not StandardMaterial3D")
			continue
		var sm := mat as StandardMaterial3D
		var want: Color = rec["tint"] as Color
		_check(sm.emission_enabled and sm.emission.is_equal_approx(want),
			"%s emits its authored lit tint %s (not white)" % [str(rec["label"]), str(want)],
			"%s emission is %s (expected %s)" % [str(rec["label"]), str(sm.emission), str(want)])
		_check(sm.emission_energy_multiplier <= float(rec["cap"]) + 0.001,
			"%s energy %.2f <= %.1f" % [str(rec["label"]), sm.emission_energy_multiplier, float(rec["cap"])],
			"%s energy %.2f above the %.1f family cap" % [str(rec["label"]), sm.emission_energy_multiplier, float(rec["cap"])])


## W6L #6b: no material may emit pure white above 4 (authored strength included).
func check_emissive_ceiling_audit() -> void:
	var db := _db()
	var checked: int = 0
	var bad_energy: Array[String] = []
	var bad_white: Array[String] = []
	for key_v: Variant in db.keys():
		var info: Dictionary = db[key_v] as Dictionary
		if info.is_empty():
			continue
		var texs: Dictionary = info.get("texs", {})
		var probe := StandardMaterial3D.new()
		if str(texs.get("emissive", "")) != "" and bool(ll.call("_ue_emissive_allowed", info)):
			# Mirror the loader: an emissive texture starts at 2.2.
			probe.emission_enabled = true
			probe.emission_energy_multiplier = 2.2
		ll.call("_apply_ue_emissive", probe, info)
		checked += 1
		if not probe.emission_enabled:
			continue
		if probe.emission_energy_multiplier > EMISSIVE_CEIL + 0.001:
			bad_energy.append("%s (%.2f)" % [str(key_v).get_file(), probe.emission_energy_multiplier])
		if minf(probe.emission.r, minf(probe.emission.g, probe.emission.b)) >= PURE_WHITE_MIN \
				and probe.emission_energy_multiplier > EMISSIVE_CEIL + 0.001:
			bad_white.append(str(key_v).get_file())
	_check(checked > 1000,
		"emissive ceiling audit walked %d generated materials" % checked,
		"emissive audit walked only %d materials" % checked)
	_check(bad_energy.is_empty(),
		"no material exceeds the global emissive ceiling %.1f" % EMISSIVE_CEIL,
		"materials above the global ceiling: " + str(bad_energy))
	_check(bad_white.is_empty(),
		"no material emits pure white above %.1f" % EMISSIVE_CEIL,
		"pure-white emitters above the ceiling: " + str(bad_white))


## W6L #7: mask-based glass caps opacity_scale at 1.0 (Den pane no longer
## saturates at mask 0.51), while mask-less glass keeps its authored scalar.
func check_den_pane() -> void:
	var pane: Material = ll.call("get_material_for_ue", DEN_PANE_OLD)
	if pane is ShaderMaterial:
		var s := pane as ShaderMaterial
		var scale: float = float(s.get_shader_parameter("opacity_scale"))
		var raw: float = 0.51 * scale
		var centre: float = clampf(raw * 0.42, 0.04, 0.92)
		_check(scale <= 1.0 + 0.001,
			"ThievesDen pane (MI_GlassPanels_oldmanor) opacity_scale capped at %.2f" % scale,
			"ThievesDen pane opacity_scale %.2f (authored 2.0 still multiplies the mask)" % scale)
		_check(raw <= 0.5101,
			"raw alpha at mask 0.51 is %.3f (no longer saturated)" % raw,
			"raw alpha at mask 0.51 is %.3f (saturated)" % raw)
		_check(centre >= 0.15 and centre <= 0.30,
			"centre transmission at mask 0.51 is %.3f (thin-glass floor, rim kept)" % centre,
			"centre transmission %.3f outside the 0.15..0.30 band" % centre)
	else:
		_check(false, "ThievesDen pane builds the glass shader", "Den pane is not a ShaderMaterial")
	var pane2: Material = ll.call("get_material_for_ue", DEN_PANE)
	if pane2 is ShaderMaterial:
		var s2 := pane2 as ShaderMaterial
		_check(float(s2.get_shader_parameter("opacity_scale")) <= 1.0 + 0.001,
			"MI_GlassPanels opacity_scale capped at 1.0",
			"MI_GlassPanels opacity_scale %.2f" % float(s2.get_shader_parameter("opacity_scale")))
	else:
		_check(false, "MI_GlassPanels builds the glass shader", "MI_GlassPanels not a ShaderMaterial")
	# Scope: the cap only applies when an opacity map is bound.
	var maskless := {"params": {"Opacity": 2.0}, "texs": {}}
	var mat_a: Material = ll.call("_build_glass_material", maskless, null, null)
	if mat_a is ShaderMaterial:
		_check(is_equal_approx(float((mat_a as ShaderMaterial).get_shader_parameter("opacity_scale")), 2.0),
			"control: mask-less glass keeps its authored opacity 2.0",
			"mask-less glass was capped: %.2f" % float((mat_a as ShaderMaterial).get_shader_parameter("opacity_scale")))
	var op_tex: Texture2D = ll.call("_load_tex", "res://assets/ue/Raw/MaterialLibrary/Environment/Glass/WIndowPanels/T_DisplayGlass_O.png") as Texture2D
	var mat_b: Material = ll.call("_build_glass_material", maskless, null, op_tex)
	if mat_b is ShaderMaterial:
		_check(is_equal_approx(float((mat_b as ShaderMaterial).get_shader_parameter("opacity_scale")), 1.0),
			"masked glass with authored opacity 2.0 caps to 1.0",
			"masked glass kept %.2f" % float((mat_b as ShaderMaterial).get_shader_parameter("opacity_scale")))


## W6L #8: backlight only for authored foliage, never flat subsurface cards.
func check_foliage_backlight() -> void:
	for rec: Dictionary in [
		{"path": POSTER_MI, "label": "MI_PosterWanted"},
		{"path": POSTER_A_MI, "label": "MI_PosterA"},
		{"path": DECAL_POSTER_MI, "label": "MI_DecalPosters"},
		{"path": COINS_MI, "label": "MI_Coins"},
	]:
		var mat: Material = ll.call("get_material_for_ue", str(rec["path"]))
		if mat is StandardMaterial3D:
			_check(not (mat as StandardMaterial3D).backlight_enabled,
				"%s has no backlight (MSM_Subsurface is not foliage)" % str(rec["label"]),
				"%s still has backlight_enabled" % str(rec["label"]))
		else:
			_check(false, "%s builds a StandardMaterial3D" % str(rec["label"]), "not StandardMaterial3D")
	for rec2: Dictionary in [
		{"path": BIRCH_LEAVES_MI, "label": "MI_BirchLeaves", "want": true},
		{"path": PINE_NEEDLES_MI, "label": "MI_ISMPineNeedles", "want": true},
		{"path": BIRCH_BARK_MI, "label": "MI_BirchBark", "want": false},
	]:
		var mat2: Material = ll.call("get_material_for_ue", str(rec2["path"]))
		if mat2 is StandardMaterial3D:
			_check((mat2 as StandardMaterial3D).backlight_enabled == bool(rec2["want"]),
				"%s backlight=%s (authored foliage rule)" % [str(rec2["label"]), str(rec2["want"])],
				"%s backlight changed" % str(rec2["label"]))
		else:
			_check(false, "%s builds a StandardMaterial3D" % str(rec2["label"]), "not StandardMaterial3D")
	var db := _db()
	var poster_info: Dictionary = db.get(POSTER_MI, {})
	var leaves_info: Dictionary = db.get(BIRCH_LEAVES_MI, {})
	_check(not bool(ll.call("_is_authored_foliage", poster_info, "EMaterialShadingModel::MSM_Subsurface")),
		"poster MSM_Subsurface is not classified as foliage",
		"poster MSM_Subsurface is still classified as foliage")
	_check(bool(ll.call("_is_authored_foliage", leaves_info, "EMaterialShadingModel::MSM_Subsurface")),
		"birch leaves MSM_Subsurface is classified as foliage",
		"birch leaves lost the foliage classification")
	var synth: Dictionary = {"path": "/Game/ThirdParty/Stylized_forest_2/Materials/Trees/M_FoliageBase", "texs": {}}
	_check(bool(ll.call("_is_authored_foliage", synth, "EMaterialShadingModel::MSM_TwoSidedFoliage")),
		"MSM_TwoSidedFoliage is foliage regardless of tokens",
		"MSM_TwoSidedFoliage lost the foliage classification")
