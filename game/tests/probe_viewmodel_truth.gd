extends SceneTree
## Regression probe for two shipped-asset truths:
## 1. MI_Zipwire / MI_ThiefNisha_Top must not bind the wall-light emissive map
##    when Emissive On? is false.
## 2. The visible zipwire crank mesh is weighted to crank_arm, not crank_handle.

func _init() -> void:
	call_deferred("_run")


func _find_shader_with_tex(root: Node, tex_substr: String) -> ShaderMaterial:
	if root == null:
		return null
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_active_material(s)
			if m is ShaderMaterial:
				var sm: ShaderMaterial = m as ShaderMaterial
				var alb: Variant = sm.get_shader_parameter("albedo_tex")
				if alb is Texture2D and (alb as Texture2D).resource_path.find(tex_substr) >= 0:
					return sm
	return null


func _run() -> void:
	var player: CharacterBody3D = (load("res://src/player/thief_character.gd") as GDScript).new() as CharacterBody3D
	root.add_child(player)
	await process_frame
	await process_frame
	player.set_physics_process(false)
	player.call("equip_tool", "zipwire")
	await process_frame
	await process_frame

	var zip_mat: ShaderMaterial = _find_shader_with_tex(player.get("fp_tool_root") as Node, "T_Zipwire_D")
	var zip_use_em: bool = zip_mat != null and zip_mat.get_shader_parameter("use_emission_tex") == true
	var zip_em_tex: Variant = zip_mat.get_shader_parameter("emission_tex") if zip_mat != null else null
	var zip_clean: bool = zip_mat != null and not zip_use_em \
		and (zip_em_tex == null or not (zip_em_tex is Texture2D) or (zip_em_tex as Texture2D).resource_path.find("T_LightWallCastleSm_E") < 0)
	var top_mat: ShaderMaterial = _find_shader_with_tex(player.get("_fp_arm_holder") as Node, "T_ThiefNisha_Top_D")
	var top_use_em: bool = top_mat != null and top_mat.get_shader_parameter("use_emission_tex") == true
	var top_em_tex: Variant = top_mat.get_shader_parameter("emission_tex") if top_mat != null else null
	var top_clean: bool = top_mat != null and not top_use_em \
		and (top_em_tex == null or not (top_em_tex is Texture2D) or (top_em_tex as Texture2D).resource_path.find("T_LightWallCastleSm_E") < 0)

	var tool_root: Node = player.get("fp_tool_root") as Node
	var arm_idx: int = -1
	var arm_skel: Skeleton3D = null
	if tool_root != null:
		for n: Node in tool_root.find_children("*", "Skeleton3D", true, false):
			var sk: Skeleton3D = n as Skeleton3D
			if sk != null:
				var bi: int = sk.find_bone("crank_arm")
				if bi >= 0:
					arm_skel = sk
					arm_idx = bi
					break
	var crank_ok: bool = false
	if arm_skel != null and arm_idx >= 0:
		player.set("crank_progress", 0.5)
		player.call("_tp_crank_tick")
		var posed: Quaternion = arm_skel.get_bone_pose_rotation(arm_idx)
		player.call("_tp_crank_reset_handle")
		var rest: Quaternion = arm_skel.get_bone_pose_rotation(arm_idx)
		crank_ok = not posed.is_equal_approx(Quaternion.IDENTITY) and rest.is_equal_approx(Quaternion.IDENTITY)

	if not zip_clean or not top_clean or not crank_ok:
		printerr("VIEWMODEL_TRUTH FAIL zip=", zip_clean, " top=", top_clean, " crank=", crank_ok, " arm_idx=", arm_idx)
		quit(1)
		return
	print("VIEWMODEL_TRUTH PASS zip_emissive=off top_emissive=off crank_bone=crank_arm posed=true reset=true")
	if is_instance_valid(player):
		player.queue_free()
	await process_frame
	quit(0)
