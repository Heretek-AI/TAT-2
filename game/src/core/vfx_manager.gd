class_name VfxManager
extends RefCounted


static func spawn_smoke_cloud(parent: Node, pos: Vector3, radius: float, ttl: float) -> void:
	if parent == null:
		return
	var root: Node3D = Node3D.new()
	root.name = "SmokeCloud"
	parent.add_child(root)
	root.global_position = pos

	var puff_mesh: SphereMesh = SphereMesh.new()
	puff_mesh.radius = 0.9
	puff_mesh.height = 1.8
	puff_mesh.radial_segments = 12
	puff_mesh.rings = 8

	var puff_mat: StandardMaterial3D = StandardMaterial3D.new()
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.albedo_color = Color(0.22, 0.25, 0.3, 0.45)
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	puff_mesh.material = puff_mat

	var smoke: CPUParticles3D = CPUParticles3D.new()
	smoke.name = "SmokeParticles"
	smoke.amount = 36
	smoke.lifetime = 2.5
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	smoke.emitting = true
	smoke.mesh = puff_mesh
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = radius * 0.45
	smoke.gravity = Vector3(0.0, 0.25, 0.0)
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 1.2
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.4
	root.add_child(smoke)

	var inner_mesh: SphereMesh = SphereMesh.new()
	inner_mesh.radius = radius * 0.5
	inner_mesh.height = radius
	inner_mesh.radial_segments = 16
	inner_mesh.rings = 12

	var inner_mat: StandardMaterial3D = StandardMaterial3D.new()
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.albedo_color = Color(0.3, 0.33, 0.38, 0.35)
	inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	inner_mesh.material = inner_mat

	var inner: MeshInstance3D = MeshInstance3D.new()
	inner.name = "InnerPuff"
	inner.mesh = inner_mesh
	root.add_child(inner)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		return
	var fade_tween: Tween = tree.create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(inner, "scale", Vector3.ONE * 1.4, ttl)
	fade_tween.tween_property(inner_mat, "albedo_color:a", 0.0, ttl)
	tree.create_timer(ttl).timeout.connect(root.queue_free)


static func spawn_fairy_orb(parent: Node, from_pos: Vector3, to_pos: Vector3) -> void:
	if parent == null:
		return
	var root: Node3D = Node3D.new()
	root.name = "FairyOrb"
	parent.add_child(root)
	root.global_position = from_pos

	var orb_mesh: SphereMesh = SphereMesh.new()
	orb_mesh.radius = 0.16
	orb_mesh.height = 0.32
	orb_mesh.radial_segments = 16
	orb_mesh.rings = 12

	var orb_mat: StandardMaterial3D = StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.albedo_color = Color(0.55, 0.95, 1.0, 1.0)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(0.4, 0.9, 1.0, 1.0)
	orb_mat.emission_energy_multiplier = 2.0
	orb_mesh.material = orb_mat

	var orb: MeshInstance3D = MeshInstance3D.new()
	orb.name = "OrbMesh"
	orb.mesh = orb_mesh
	root.add_child(orb)

	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "OrbLight"
	glow.light_color = Color(0.4, 0.95, 1.0)
	glow.omni_range = 4.0
	glow.light_energy = 1.2
	root.add_child(glow)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		root.queue_free()
		return
	var tween: Tween = tree.create_tween()
	tween.tween_property(root, "global_position", to_pos, 0.45)
	tween.tween_callback(root.queue_free)


static func spawn_grapple_beam(parent: Node, from_pos: Vector3, to_pos: Vector3, ttl: float = 0.35) -> void:
	if parent == null:
		return
	var offset: Vector3 = to_pos - from_pos
	var dist: float = offset.length()
	if dist < 0.001:
		return
	var midpoint: Vector3 = (from_pos + to_pos) * 0.5

	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = dist
	cyl.radial_segments = 12
	cyl.rings = 1

	var beam_mat: StandardMaterial3D = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(0.45, 0.9, 1.0, 0.9)
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(0.35, 0.85, 1.0, 1.0)
	beam_mat.emission_energy_multiplier = 2.5
	cyl.material = beam_mat

	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.name = "GrappleBeam"
	beam.mesh = cyl
	parent.add_child(beam)
	beam.global_position = midpoint

	var y_axis: Vector3 = offset / dist
	var up_hint: Vector3 = Vector3.UP
	if absf(y_axis.dot(Vector3.UP)) > 0.99:
		up_hint = Vector3.RIGHT
	var x_axis: Vector3 = up_hint.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	beam.basis = Basis(x_axis, y_axis, z_axis)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		beam.queue_free()
		return
	tree.create_timer(ttl).timeout.connect(beam.queue_free)


static func spawn_sap_burst(parent: Node, pos: Vector3) -> void:
	if parent == null:
		return
	var root: Node3D = Node3D.new()
	root.name = "SapBurst"
	parent.add_child(root)
	root.global_position = pos

	var spark_mesh: SphereMesh = SphereMesh.new()
	spark_mesh.radius = 0.06
	spark_mesh.height = 0.12
	spark_mesh.radial_segments = 8
	spark_mesh.rings = 4

	var spark_mat: StandardMaterial3D = StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(0.35, 1.0, 0.75, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(0.3, 1.0, 0.7, 1.0)
	spark_mat.emission_energy_multiplier = 3.0
	spark_mesh.material = spark_mat

	var sparks: CPUParticles3D = CPUParticles3D.new()
	sparks.name = "SapSparks"
	sparks.amount = 28
	sparks.lifetime = 0.7
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.emitting = true
	sparks.mesh = spark_mesh
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.25
	sparks.gravity = Vector3(0.0, -2.0, 0.0)
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	root.add_child(sparks)

	var flash: OmniLight3D = OmniLight3D.new()
	flash.name = "SapFlash"
	flash.light_color = Color(0.4, 1.0, 0.75)
	flash.omni_range = 5.0
	flash.light_energy = 2.0
	root.add_child(flash)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		return
	var fade_tween: Tween = tree.create_tween()
	fade_tween.tween_property(flash, "light_energy", 0.0, 0.9)
	tree.create_timer(0.9).timeout.connect(root.queue_free)


static func spawn_candle_flame(parent: Node, pos: Vector3) -> void:
	if parent == null:
		return
	var root: Node3D = Node3D.new()
	root.name = "CandleFlame"
	parent.add_child(root)
	root.global_position = pos

	var flame_mesh: SphereMesh = SphereMesh.new()
	flame_mesh.radius = 0.04
	flame_mesh.height = 0.08
	flame_mesh.radial_segments = 8
	flame_mesh.rings = 4

	var flame_mat: StandardMaterial3D = StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.9)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.55, 0.15, 1.0)
	flame_mat.emission_energy_multiplier = 2.0
	flame_mesh.material = flame_mat

	var flame: CPUParticles3D = CPUParticles3D.new()
	flame.name = "FlameParticles"
	flame.amount = 8
	flame.lifetime = 0.6
	flame.emitting = true
	flame.mesh = flame_mesh
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.03
	flame.gravity = Vector3(0.0, 0.8, 0.0)
	flame.initial_velocity_min = 0.05
	flame.initial_velocity_max = 0.2
	flame.scale_amount_min = 0.7
	flame.scale_amount_max = 1.1
	root.add_child(flame)


static func spawn_lockpick_sparks(parent: Node, pos: Vector3) -> void:
	if parent == null:
		return
	var root: Node3D = Node3D.new()
	root.name = "LockpickSparks"
	parent.add_child(root)
	root.global_position = pos

	var spark_mesh: BoxMesh = BoxMesh.new()
	spark_mesh.size = Vector3(0.03, 0.03, 0.03)

	var spark_mat: StandardMaterial3D = StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.78, 0.25, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.78, 0.25, 1.0)
	spark_mat.emission_energy_multiplier = 2.5
	spark_mesh.material = spark_mat

	var sparks: CPUParticles3D = CPUParticles3D.new()
	sparks.name = "LockpickSparkParticles"
	sparks.amount = 14
	sparks.lifetime = 0.35
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.emitting = true
	sparks.mesh = spark_mesh
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.08
	sparks.gravity = Vector3(0.0, -3.0, 0.0)
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 4.5
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	root.add_child(sparks)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		return
	tree.create_timer(0.6).timeout.connect(root.queue_free)


static func spawn_blackjack_swing(parent: Node, pos: Vector3, dir: Vector3) -> void:
	if parent == null:
		return
	var safe_dir: Vector3 = dir
	if safe_dir.length() < 0.001:
		safe_dir = Vector3.FORWARD
	safe_dir = safe_dir.normalized()

	var root: Node3D = Node3D.new()
	root.name = "BlackjackSwing"
	parent.add_child(root)
	root.global_position = pos

	var z_axis: Vector3 = safe_dir
	var up_hint: Vector3 = Vector3.UP
	if absf(z_axis.dot(Vector3.UP)) > 0.99:
		up_hint = Vector3.RIGHT
	var x_axis: Vector3 = up_hint.cross(z_axis).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	root.basis = Basis(x_axis, y_axis, z_axis)

	var streak_mesh: BoxMesh = BoxMesh.new()
	streak_mesh.size = Vector3(0.06, 0.06, 0.6)

	var streak_mat: StandardMaterial3D = StandardMaterial3D.new()
	streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	streak_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	streak_mat.albedo_color = Color(0.85, 0.9, 1.0, 0.28)
	streak_mesh.material = streak_mat

	var streak: MeshInstance3D = MeshInstance3D.new()
	streak.name = "SwingStreak"
	streak.mesh = streak_mesh
	streak.position = Vector3(0.0, 0.0, 0.3)
	root.add_child(streak)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		return
	var swing_tween: Tween = tree.create_tween()
	swing_tween.set_parallel(true)
	swing_tween.tween_property(root, "global_position", pos + safe_dir * 0.45, 0.18)
	swing_tween.tween_property(streak_mat, "albedo_color:a", 0.0, 0.18)
	tree.create_timer(0.18).timeout.connect(root.queue_free)


static func spawn_window_godray(parent: Node, pos: Vector3, target_pos: Vector3) -> void:
	if parent == null:
		return
	var offset: Vector3 = target_pos - pos
	var dist: float = offset.length()
	if dist < 0.001:
		return
	var midpoint: Vector3 = (pos + target_pos) * 0.5

	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.55
	cone.bottom_radius = 1.65
	cone.height = dist
	cone.radial_segments = 16
	cone.rings = 1

	var shaft_shader: Shader = Shader.new()
	shaft_shader.code = "shader_type spatial;\nrender_mode blend_add, unshaded, cull_disabled, depth_draw_never;\nuniform vec4 beam_color : source_color = vec4(0.45, 0.72, 0.96, 0.16);\nvoid fragment() {\n\tfloat fresnel = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);\n\tfloat axial = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.15, UV.y);\n\tALBEDO = beam_color.rgb;\n\tALPHA = beam_color.a * fresnel * axial;\n}\n"
	var shaft_mat: ShaderMaterial = ShaderMaterial.new()
	shaft_mat.shader = shaft_shader
	cone.material = shaft_mat

	var shaft: MeshInstance3D = MeshInstance3D.new()
	shaft.name = "WindowGodray"
	shaft.mesh = cone
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shaft)
	shaft.global_position = midpoint

	var y_axis: Vector3 = offset / dist
	var up_hint: Vector3 = Vector3.UP
	if absf(y_axis.dot(Vector3.UP)) > 0.99:
		up_hint = Vector3.RIGHT
	var x_axis: Vector3 = up_hint.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	shaft.basis = Basis(x_axis, y_axis, z_axis)


static func spawn_footprint_decal(pos: Vector3, forward: Vector3, is_left: bool) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var parent: Node = tree.current_scene
	if parent == null:
		parent = tree.root
	if parent == null:
		return
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat.length() < 0.01:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized()
	var side: Vector3 = flat.cross(Vector3.UP).normalized()
	var lateral: float = -0.11 if is_left else 0.11
	var foot_pos: Vector3 = pos + Vector3(0.0, 0.012, 0.0) + side * lateral
	var root: Node3D = Node3D.new()
	root.name = "FootprintLeft" if is_left else "FootprintRight"
	parent.add_child(root)
	root.global_position = foot_pos
	root.rotation.y = atan2(flat.x, flat.z)
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(0.13, 0.30)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.82, 0.92, 1.0, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.65, 0.85, 1.0, 1.0)
	mat.emission_energy_multiplier = 1.2
	quad.material = mat
	var decal: MeshInstance3D = MeshInstance3D.new()
	decal.name = "FootprintQuad"
	decal.mesh = quad
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(decal)
	var fade_tween: Tween = tree.create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(mat, "albedo_color:a", 0.0, 6.0)
	fade_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 6.0)
	tree.create_timer(6.1).timeout.connect(root.queue_free)


static func spawn_blue_wisp(parent: Node3D, local_pos: Vector3) -> Node3D:
	if parent == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "BlueWisp"
	parent.add_child(root)
	root.position = local_pos
	var orb_mesh: SphereMesh = SphereMesh.new()
	orb_mesh.radius = 0.09
	orb_mesh.height = 0.18
	orb_mesh.radial_segments = 16
	orb_mesh.rings = 12
	var orb_mat: StandardMaterial3D = StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.albedo_color = Color(0.55, 0.9, 1.0, 1.0)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(0.35, 0.8, 1.0, 1.0)
	orb_mat.emission_energy_multiplier = 3.0
	orb_mesh.material = orb_mat
	var orb: MeshInstance3D = MeshInstance3D.new()
	orb.name = "WispOrb"
	orb.mesh = orb_mesh
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(orb)
	var halo_mesh: SphereMesh = SphereMesh.new()
	halo_mesh.radius = 0.17
	halo_mesh.height = 0.34
	halo_mesh.radial_segments = 16
	halo_mesh.rings = 12
	var halo_mat: StandardMaterial3D = StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.22)
	halo_mesh.material = halo_mat
	var halo: MeshInstance3D = MeshInstance3D.new()
	halo.name = "WispHalo"
	halo.mesh = halo_mesh
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "WispLight"
	glow.light_color = Color(0.4, 0.8, 1.0)
	glow.omni_range = 6.0
	glow.light_energy = 1.5
	glow.shadow_enabled = false
	root.add_child(glow)
	var mote_mesh: SphereMesh = SphereMesh.new()
	mote_mesh.radius = 0.02
	mote_mesh.height = 0.04
	mote_mesh.radial_segments = 6
	mote_mesh.rings = 4
	var mote_mat: StandardMaterial3D = StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.albedo_color = Color(0.6, 0.95, 1.0, 1.0)
	mote_mat.emission_enabled = true
	mote_mat.emission = Color(0.5, 0.9, 1.0, 1.0)
	mote_mat.emission_energy_multiplier = 2.5
	mote_mesh.material = mote_mat
	var motes: CPUParticles3D = CPUParticles3D.new()
	motes.name = "WispMotes"
	motes.amount = 24
	motes.lifetime = 1.8
	motes.emitting = true
	motes.mesh = mote_mesh
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.12
	motes.direction = Vector3(0.0, 1.0, 0.0)
	motes.spread = 25.0
	motes.gravity = Vector3(0.0, 0.5, 0.0)
	motes.initial_velocity_min = 0.35
	motes.initial_velocity_max = 0.9
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.0
	root.add_child(motes)
	var bob_tween: Tween = orb.create_tween()
	bob_tween.set_loops()
	bob_tween.tween_property(orb, "position:y", 0.12, 1.2).set_trans(Tween.TRANS_SINE)
	bob_tween.tween_property(orb, "position:y", -0.05, 1.2).set_trans(Tween.TRANS_SINE)
	return root


static func set_prop_highlight(target: Node, enabled: bool) -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		return
	var meshes: Array = []
	if target.has_meta("_vfx_hl_meshes"):
		meshes = target.get_meta("_vfx_hl_meshes") as Array
	elif enabled:
		if target is MeshInstance3D:
			meshes.append(target as MeshInstance3D)
		var found: Array[Node] = target.find_children("*", "MeshInstance3D", true, false)
		for child: Node in found:
			if child is MeshInstance3D:
				meshes.append(child as MeshInstance3D)
		# Cache the mesh list so toggling the same target never rescans the tree.
		target.set_meta("_vfx_hl_meshes", meshes)
	for mi_var: Variant in meshes:
		# Cached entries can be freed (e.g. an interactable rebuilt its visual).
		if not is_instance_valid(mi_var):
			continue
		var mi: MeshInstance3D = mi_var as MeshInstance3D
		if mi == null:
			continue
		if enabled:
			if mi.has_meta("_vfx_hl") and bool(mi.get_meta("_vfx_hl", false)):
				continue
			mi.set_meta("_vfx_hl", true)
			mi.set_meta("_vfx_hl_orig", mi.material_overlay)
			var hl: StandardMaterial3D = StandardMaterial3D.new()
			hl.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			hl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hl.albedo_color = Color(0.45, 0.8, 1.0, 0.28)
			hl.emission_enabled = true
			hl.emission = Color(0.35, 0.75, 1.0, 1.0)
			hl.emission_energy_multiplier = 1.2
			hl.rim_enabled = true
			hl.rim = 0.6
			hl.rim_tint = 0.4
			mi.material_overlay = hl
		else:
			if not mi.has_meta("_vfx_hl"):
				continue
			var orig: Material = mi.get_meta("_vfx_hl_orig", null) as Material
			mi.material_overlay = orig
			mi.remove_meta("_vfx_hl")
			if mi.has_meta("_vfx_hl_orig"):
				mi.remove_meta("_vfx_hl_orig")
	if not enabled and target.has_meta("_vfx_hl_meshes"):
		target.remove_meta("_vfx_hl_meshes")
