extends RefCounted
## T08 — material/texture remediation checks.
##
## Shared by `tests/test_t08_materials.gd` (standalone probe, prints the
## before/after census) and by `tests/run_tests.gd` suite 91 (gate). Each check
## returns human-readable problem strings; an empty array is a pass.
##
## What is asserted, and why:
##  1. Tint colour space. UE base-colour vectors are linear; Godot's
##     `albedo_color` is sRGB-decoded. The port already converts in
##     `_apply_diffuse_mask_tint` and the storefront-decal shader but not on the
##     generic path (110,729 binds = 39 % of level binds read one gamma dark).
##     HDR (>1) carries stay untouched (loot shine / hotwire / beam card).
##  2. GLB slot index. `mesh_materials.json` is emitted in GLB primitive order
##     (0 reorderings), so index is authored truth. The old name-substring
##     match overrode it on 53 placed meshes / 776 instances and bound sibling
##     variants (Copper for plain metal, DirtLayer for metal, wood for glass).
##  3. Props instantiated outside the level build. The glTF export carries no
##     images and no baseColorFactor, so an un-rebound GLB surface is flat white
##     (the cat statue, clues, pickups, bottles, locked doors).
##  4. Debug primitives and flat-colour binds are visible, not silent:
##     MI_Default_White no longer spawns as flat white geometry, and a colour
##     with no albedo map is counted (near-white named).
##  5. Producer-side fixes (BPO blend/shading, master texture slots, tint pick).
##     These depend on regenerated `game/data/generated/materials.json`; when
##     the tree still carries the pre-T08 data the checks are SKIPped loudly so
##     another lane is never red for a missing integrator step.

const LOADER_PATH := "res://src/core/level_loader.gd"

const ENV_PROP_MI := "/Game/MaterialLibrary/Environment/MasterMaterials/Loot/M_EnvLoot"
const HOTWIRE_MI := "/Game/Art/Effects/Hotwire/M_Hotwire_Glow"
const HEAD_MI := "/Game/Art/Character/ThiefNisha/Base/MI_ThiefNisha_Head"
const WHITE_MI := "/Game/MaterialLibrary/Debug/MI_Default_White"
const CAT_MI := "/Game/Art/Gameplay/Loot/LootMajor/StatueCat/MI_CatStatueA"
const CAT_MESH := "/Game/Art/Gameplay/Loot/LootMajor/StatueCat/SM_CatStatueA"
const CAT_GLB := "res://assets/ue/Content/Art/Gameplay/Loot/LootMajor/StatueCat/SM_CatStatueA.glb"
const CAT_ALBEDO := "T_CatStatueA_D.png"

const BANK_MESH := "/Game/Art/Environment/Bank/SM_Bank_Cabins_1x4"
const BANK_PLAIN := "/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalSurfaceA"
const BANK_COPPER := "/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalSurfaceA_Copper"
const VAULT_MESH := "/Game/Art/Environment/Bank/SM_VaultDoor"
const VAULT_DIRT := "/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalSurfaceA_DirtLayer"
const CASE_MESH := "/Game/Art/Environment/Props/Furniture/Displays/DisplayPlinth/SM_DisplayCaseA"
const CASE_WOOD := "/Game/Art/Environment/Props/Furniture/Displays/DisplayPlinth/ML/MI_DisplayCaseA"
const CASE_GLASS := "/Game/Art/Environment/Props/Furniture/Displays/DisplayPlinth/MI_DisplayCaseAGlass"

const BIRCH_MI := "/Game/ThirdParty/Stylized_forest_2/Materials/Trees/M_sf2_birch_bark"
const BIRCH_ALBEDO := "t_sf2_birch_bark_base_color2.png"
const WARD_DOOR_MI := "/Game/Art/Effects/DoorWard/M_DoorWard_DoubleSided"
const WARD_DOOR_ALBEDO := "t_doorward_glyph_hand.png"
const BLOCKER_WARD_MI := "/Game/Art/Gameplay/Wards/MI_BlockerWard"
const SPRUCE_MI := "/Game/ThirdParty/Stylized_forest_2/Materials/Trees/UpdatedMaterials/MI_ISMSpruceNeedles"
const STAINED_MI := "/Game/Art/Environment/Lights/LightModules/LightsGlass/MI_LightsStainedGlass_Yellow"
const DATA_MARKER := SPRUCE_MI


## True when the tree carries the post-T08 producer output. One BPO-only
## blend-mode material is the marker: pre-T08 it has no render.blend_mode.
static func producer_data_current(db: Dictionary) -> bool:
	var rec: Variant = db.get(DATA_MARKER, null)
	if not (rec is Dictionary):
		return false
	var render: Variant = (rec as Dictionary).get("render", null)
	if not (render is Dictionary):
		return false
	return str((render as Dictionary).get("blend_mode", "")) != ""


static func run(ll: Node, db: Dictionary) -> Array[String]:
	var p: Array[String] = []
	_tint_space(ll, p)
	_slot_index(ll, p)
	_prop_glb(ll, p)
	_debug_and_flat(ll, p)
	if producer_data_current(db):
		_producer_output(ll, db, p)
	else:
		print("SKIP: T08 producer checks — materials.json predates the T08 producer (integrator: make regenerate / make normalize, re-stamp the audit baseline)")
	return p


## --- 1. tint colour space ---------------------------------------------------
static func _tint_space(ll: Node, p: Array[String]) -> void:
	var enc: Color = ll.call("_srgb_encode_albedo_tint", Color(1.0, 0.3611, 0.0777, 1.0))
	if absf(enc.g - 0.6351) > 0.002 or absf(enc.b - 0.3089) > 0.002:
		p.append("tint sRGB encode: expected (1.0, 0.635, 0.309), got %s" % str(enc))
	var hdr_in: Color = Color(5.0, 4.381, 3.516, 0.5)
	if ll.call("_srgb_encode_albedo_tint", hdr_in) != hdr_in:
		p.append("tint sRGB encode must pass HDR (>1) values through untouched")
	# Authored linear 0.361/0.0777 must reach albedo_color as sRGB, not verbatim.
	var env_mat: Material = ll.call("get_material_for_ue", ENV_PROP_MI) as Material
	if not (env_mat is StandardMaterial3D):
		p.append("M_EnvLoot did not build a StandardMaterial3D")
	else:
		var sm: StandardMaterial3D = env_mat as StandardMaterial3D
		if sm.albedo_texture == null:
			p.append("M_EnvLoot lost its albedo map")
		if sm.albedo_color.g < 0.62 or sm.albedo_color.g > 0.65:
			p.append("M_EnvLoot albedo_color.g=%.4f is not sRGB(0.3611)=0.6345 (linear-as-sRGB regression)" % sm.albedo_color.g)
	# HDR tint with an albedo map keeps the legacy pass-through.
	var hot: Material = ll.call("get_material_for_ue", HOTWIRE_MI) as Material
	if hot is StandardMaterial3D:
		var hc: Color = (hot as StandardMaterial3D).albedo_color
		if absf(hc.g - 5.0) > 0.01 or absf(hc.b - 2.0) > 0.01:
			p.append("M_Hotwire_Glow HDR tint was encoded (expected 0,5,2; got %s)" % str(hc))
	else:
		p.append("M_Hotwire_Glow did not build a StandardMaterial3D")
	# A textured character material must not be tinted into a flat colour.
	var head: Material = ll.call("get_material_for_ue", HEAD_MI) as Material
	if head is StandardMaterial3D and (head as StandardMaterial3D).albedo_texture == null:
		p.append("MI_ThiefNisha_Head lost its albedo map")


## --- 2. GLB slot index is authored truth ------------------------------------
static func _slot_index(ll: Node, p: Array[String]) -> void:
	_check_slot(ll, p, BANK_MESH, 1, BANK_PLAIN, BANK_COPPER)
	_check_slot(ll, p, VAULT_MESH, 2, BANK_PLAIN, VAULT_DIRT)
	_check_slot(ll, p, CASE_MESH, 1, CASE_GLASS, CASE_WOOD)
	var rescued: int = int(ll.get("slot_name_fallback_count"))
	if rescued != 0:
		p.append("slot_name_fallback fired %d time(s) on the shipped data (expected 0): %s" % [
			rescued, str(ll.get("slot_name_fallback_names"))])


static func _check_slot(ll: Node, p: Array[String], mesh: String, idx: int, expect: String, wrong: String) -> void:
	var info: Dictionary = ll.call("_get_mesh_and_shape", mesh)
	var m: Mesh = info.get("mesh") as Mesh
	if m == null:
		p.append("mesh did not load: %s" % mesh)
		return
	if idx >= m.get_surface_count():
		p.append("%s has %d surfaces, expected > %d" % [mesh, m.get_surface_count(), idx])
		return
	var want: Material = ll.call("get_material_for_ue", expect) as Material
	var not_want: Material = ll.call("get_material_for_ue", wrong) as Material
	var got: Material = m.surface_get_material(idx)
	if got == null:
		p.append("%s surface %d has no material (expected %s)" % [mesh, idx, expect])
	elif got == not_want:
		p.append("%s surface %d bound %s by name instead of index %s" % [mesh, idx, wrong, expect])
	elif got != want:
		p.append("%s surface %d bound an unexpected material (expected index %s)" % [mesh, idx, expect])


## --- 3. GLB props outside the level build -----------------------------------
static func _prop_glb(ll: Node, p: Array[String]) -> void:
	if not ResourceLoader.exists(CAT_GLB):
		p.append("missing %s (extracted tree incomplete?)" % CAT_GLB)
		return
	var packed: PackedScene = ResourceLoader.load(CAT_GLB) as PackedScene
	if packed == null:
		p.append("cannot load %s as a PackedScene" % CAT_GLB)
		return
	var inst: Node3D = packed.instantiate() as Node3D
	if inst == null:
		p.append("cannot instantiate %s" % CAT_GLB)
		return
	var holder: Node3D = Node3D.new()
	holder.add_child(inst)
	ll.add_child(holder)  # the binder needs a live tree to find the loader
	var mi: MeshInstance3D = null
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		mi = n as MeshInstance3D
		break
	if mi == null or mi.mesh == null:
		p.append("SM_CatStatueA.glb has no MeshInstance3D surface")
		holder.queue_free()
		return
	var raw: Material = mi.get_surface_override_material(0)
	if raw == null:
		var base: Material = mi.mesh.surface_get_material(0)
		if base is StandardMaterial3D and (base as StandardMaterial3D).albedo_texture != null:
			p.append("control: the raw GLB already had an albedo map (the export should carry none)")
	ll.call("bind_prop_scene_materials", inst, CAT_GLB)
	var bound: Material = mi.get_surface_override_material(0)
	if not (bound is StandardMaterial3D):
		p.append("bind_prop_scene_materials did not set a StandardMaterial3D override on the loot prop")
	else:
		var bt: Texture2D = (bound as StandardMaterial3D).albedo_texture
		if bt == null or not bt.resource_path.ends_with(CAT_ALBEDO):
			p.append("loot prop albedo is %s (expected %s)" % [
				bt.resource_path if bt != null else "null", CAT_ALBEDO])
	holder.queue_free()


## --- 4. debug primitives + flat-colour visibility ---------------------------
static func _debug_and_flat(ll: Node, p: Array[String]) -> void:
	var sphere: Dictionary = {"mesh": "/Game/Test/Art/Primitives/SM_Shape_Sphere"}
	if ll.call("_is_debug_shape_mesh", "/game/test/art/primitives/sm_shape_sphere", sphere) != true:
		p.append("SM_Shape_Sphere is not recognised as an untextured debug primitive")
	var moon: Dictionary = {
		"mesh": "/Game/Test/Art/Primitives/SM_Shape_Plane",
		"override_materials": ["/Game/Art/Environment/Lights/Moonshape/MI_MoonshapeEmissive"],
	}
	if ll.call("_is_debug_shape_mesh", "/game/test/art/primitives/sm_shape_plane", moon) == true:
		p.append("an overridden SM_Shape_Plane (Den window backlight) must never be hidden")
	var cube: Dictionary = {"mesh": "/Engine/BasicShapes/Cube"}
	if ll.call("_is_debug_shape_mesh", "/engine/basicshapes/cube", cube) == true:
		p.append("/Engine/BasicShapes volumes must never be hidden")
	var wm: Material = ll.call("get_material_for_ue", WHITE_MI) as Material
	if not (wm is StandardMaterial3D):
		p.append("MI_Default_White did not build a StandardMaterial3D")
	else:
		var ws: StandardMaterial3D = wm as StandardMaterial3D
		if ws.albedo_texture != null:
			p.append("MI_Default_White unexpectedly has an albedo map")
		if int(ll.get("flat_colour_material_count")) < 1:
			p.append("the flat-colour path is still silent (count=0 after MI_Default_White)")


## --- 5. producer output (requires regenerated materials.json) ---------------
static func _producer_output(ll: Node, db: Dictionary, p: Array[String]) -> void:
	var birch: Dictionary = db.get(BIRCH_MI, {}) as Dictionary
	var birch_alb: String = str((birch.get("texs", {}) as Dictionary).get("albedo", "")).to_lower()
	if not birch_alb.ends_with(BIRCH_ALBEDO):
		p.append("M_sf2_birch_bark albedo is %s (expected its own authored %s)" % [birch_alb, BIRCH_ALBEDO])
	var wd: Dictionary = db.get(WARD_DOOR_MI, {}) as Dictionary
	var wd_alb: String = str((wd.get("texs", {}) as Dictionary).get("albedo", "")).to_lower()
	if not wd_alb.ends_with(WARD_DOOR_ALBEDO):
		p.append("M_DoorWard_DoubleSided albedo is %s (expected the authored glyph %s)" % [wd_alb, WARD_DOOR_ALBEDO])
	var bw: Dictionary = db.get(BLOCKER_WARD_MI, {}) as Dictionary
	var bw_alb: String = str((bw.get("texs", {}) as Dictionary).get("albedo", "")).to_lower()
	if "wardrobe" in bw_alb:
		p.append("MI_BlockerWard still binds the guessed wardrobe albedo %s" % bw_alb)
	if str(bw.get("albedo_source", "")) != "none":
		p.append("MI_BlockerWard albedo_source=%s (expected none: it has no authored albedo)" % str(bw.get("albedo_source")))
	for mi: String in [SPRUCE_MI, STAINED_MI]:
		var r: Dictionary = (db.get(mi, {}) as Dictionary).get("render", {}) as Dictionary
		if str(r.get("blend_mode", "")).to_lower().find("masked") < 0:
			p.append("%s lost its BasePropertyOverrides Masked blend (%s)" % [mi, str(r.get("blend_mode", ""))])
	var cat: Dictionary = db.get(CAT_MI, {}) as Dictionary
	var cat_tint: Variant = cat.get("tint", null)
	if cat_tint is Array and (cat_tint as Array).size() >= 3 and maxf(
			float((cat_tint as Array)[0]), maxf(float((cat_tint as Array)[1]), float((cat_tint as Array)[2]))) > 1.0:
		p.append("MI_CatStatueA still carries the HDR shine colour as its albedo tint %s" % str(cat_tint))
	var cat_mat: Material = ll.call("get_material_for_ue", CAT_MI) as Material
	if cat_mat is StandardMaterial3D:
		var cs: StandardMaterial3D = cat_mat as StandardMaterial3D
		if cs.albedo_texture == null:
			p.append("MI_CatStatueA lost its albedo map")
		if cs.albedo_color.r > 1.0:
			p.append("MI_CatStatueA albedo_color.r=%.1f is still an HDR albedo multiplier" % cs.albedo_color.r)
