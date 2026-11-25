extends SceneTree
## T08 S3 red proof — reproduces the three material-binding defects on the
## PRE-FIX tree. This file is evidence, not a gate: it exits 0 when the defect
## is REPRODUCED and 1 when the tree already carries the fix, so it can never be
## mistaken for a passing regression test.
##
## Recorded against fb93f84 (the T08 base commit):
##   tools/godot --headless --path game --script res://tests/probe_t08_red.gd
##   T08_RED tint_applied_linear=1 (M_EnvLoot albedo_color=(1.0, 0.361, 0.078) — authored linear copied verbatim; expected sRGB (1.0, 0.635, 0.309))
##   T08_RED slot_name_override=1 (SM_Bank_Cabins_1x4 surface 1 -> MI_TrimMetalSurfaceA_Copper, authored slot 1 = MI_TrimMetalSurfaceA)
##   T08_RED raw_glb_white=1 (SM_CatStatueA.glb surface 0 albedo_texture=null)
##   T08_RED: reproduced=3/3

const LOADER_PATH := "res://src/core/level_loader.gd"
const ENV_PROP_MI := "/Game/MaterialLibrary/Environment/MasterMaterials/Loot/M_EnvLoot"
const BANK_MESH := "/Game/Art/Environment/Bank/SM_Bank_Cabins_1x4"
const BANK_COPPER := "MI_TrimMetalSurfaceA_Copper"
const CAT_GLB := "res://assets/ue/Content/Art/Gameplay/Loot/LootMajor/StatueCat/SM_CatStatueA.glb"

var reproduced: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var ll: Node = (load(LOADER_PATH) as GDScript).new()
	get_root().add_child(ll)
	ll.call("_load_material_dbs")

	# 1. Linear authored tint copied into the sRGB albedo_color slot.
	var mat: Material = ll.call("get_material_for_ue", ENV_PROP_MI) as Material
	if mat is StandardMaterial3D:
		var c: Color = (mat as StandardMaterial3D).albedo_color
		var linear_applied: bool = absf(c.g - 0.3611) < 0.01
		print("T08_RED tint_applied_linear=", int(linear_applied),
			" (M_EnvLoot albedo_color=", c, ")")
		if linear_applied:
			reproduced += 1
	else:
		print("T08_RED tint_applied_linear=SKIP (M_EnvLoot not a StandardMaterial3D)")

	# 2. Name-substring match overrides the authored slot index.
	var info: Dictionary = ll.call("_get_mesh_and_shape", BANK_MESH)
	var m: Mesh = info.get("mesh") as Mesh
	if m != null and m.get_surface_count() > 1:
		var sm: Material = m.surface_get_material(1)
		var bound: String = ""
		if sm is StandardMaterial3D and (sm as StandardMaterial3D).albedo_texture != null:
			bound = (sm as StandardMaterial3D).albedo_texture.resource_path
		var copper: Material = ll.call("get_material_for_ue",
			"/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalSurfaceA_Copper") as Material
		var is_copper: bool = sm == copper
		print("T08_RED slot_name_override=", int(is_copper),
			" (SM_Bank_Cabins_1x4 surface 1 -> ", "MI_TrimMetalSurfaceA_Copper" if is_copper else bound, ")")
		if is_copper:
			reproduced += 1

	# 3. A GLB instantiated outside the level build has no albedo map at all.
	if ResourceLoader.exists(CAT_GLB):
		var packed: PackedScene = ResourceLoader.load(CAT_GLB) as PackedScene
		var inst: Node3D = packed.instantiate() as Node3D
		get_root().add_child(inst)
		var mi: MeshInstance3D = null
		for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
			mi = n as MeshInstance3D
			break
		if mi != null and mi.mesh != null:
			var albedos: int = 0
			for s: int in range(mi.mesh.get_surface_count()):
				var surf: Material = mi.mesh.surface_get_material(s)
				if surf is StandardMaterial3D and (surf as StandardMaterial3D).albedo_texture != null:
					albedos += 1
			var bound: int = 0
			var scr: GDScript = load(LOADER_PATH) as GDScript
			if scr != null and scr.has_method("bind_prop_scene_materials"):
				bound = int(scr.call("bind_prop_scene_materials", inst, CAT_GLB))
			print("T08_RED raw_glb_white=", int(albedos == 0),
				" bound_after=", bound,
				" (SM_CatStatueA.glb surfaces with a raw albedo map: ", albedos,
				"; surfaces rebound from mesh_materials.json: ", bound, ")")
			if albedos == 0 and bound == 0:
				reproduced += 1
		inst.queue_free()

	print("T08_RED: reproduced=%d/3" % reproduced)
	quit(0 if reproduced > 0 else 1)
