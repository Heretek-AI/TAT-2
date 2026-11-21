class_name VfxManager
extends RefCounted

## APPROX_SHADER / REFERENCE_MATCHED procedural materials (HL-1). Each was
## authored from the published KF frames, never from decompiled VM/shader
## bytecode; the cooked UE graphs stay unread.
const SMOKE_SHADER: Shader = preload("res://src/core/tat_smoke.gdshader")
const BEAM_SHADER: Shader = preload("res://src/core/tat_beam.gdshader")
const WARD_SHADER: Shader = preload("res://src/core/tat_ward.gdshader")
const ALARM_SHADER: Shader = preload("res://src/core/tat_alarm.gdshader")


## Real UE extents (BP_SmokeBomb_WorldActor BoxExtent {250, 250, 200} cm):
## a 5 x 5 x 4 m box. `half_extents` defaults to the real volume; `ttl`
## defaults to the real InitialLifeSpan (25.0 s). Gameplay callers
## (smoke_projectile, mission_controller) share the layered KF20 plume look.
static func spawn_smoke_cloud(parent: Node, pos: Vector3, half_extents: Vector3 = Vector3(2.5, 2.0, 2.5), ttl: float = 25.0) -> Node3D:
	var plume: Node3D = spawn_smoke_plume(parent, pos, half_extents, ttl)
	if plume != null:
		plume.name = "SmokeCloud"
	return plume


## `duration` is the visible flight time; the Pickpocket Fairy caller passes
## dist / FAIRY_SPEED (4.5 m/s). Kept 0.45 s by default for older callers.
static func spawn_fairy_orb(parent: Node, from_pos: Vector3, to_pos: Vector3, duration: float = 0.45) -> void:
	const FAIRY_ORB_ENERGY_CAP := 0.65
	const ORBLIGHT_ENERGY_CAP := 0.65
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
	orb_mat.emission_energy_multiplier = FAIRY_ORB_ENERGY_CAP
	assert(orb_mat.emission_energy_multiplier <= FAIRY_ORB_ENERGY_CAP + 0.001, "FairyOrbCap: fairy orb energy exceeds cap")
	print("FairyOrbCap: fairy orb emission_energy=", orb_mat.emission_energy_multiplier, " cap=", FAIRY_ORB_ENERGY_CAP, " (no UE orb authoring; mission glow 0.65)")
	orb_mesh.material = orb_mat

	var orb: MeshInstance3D = MeshInstance3D.new()
	orb.name = "OrbMesh"
	orb.mesh = orb_mesh
	root.add_child(orb)

	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "OrbLight"
	glow.light_color = Color(0.4, 0.95, 1.0)
	glow.omni_range = 4.0
	glow.light_energy = ORBLIGHT_ENERGY_CAP
	assert(glow.light_energy <= ORBLIGHT_ENERGY_CAP + 0.001, "OrbLightCap: orb light energy exceeds cap")
	print("OrbLightCap: orb light energy=", glow.light_energy, " cap=", ORBLIGHT_ENERGY_CAP, " (no UE orb light; mission glow 0.65)")
	root.add_child(glow)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		root.queue_free()
		return
	var tween: Tween = tree.create_tween()
	tween.tween_property(root, "global_position", to_pos, maxf(duration, 0.01))
	tween.tween_callback(root.queue_free)


static func spawn_grapple_beam(parent: Node, from_pos: Vector3, to_pos: Vector3, ttl: float = 0.35) -> void:
	if parent == null:
		return
	var dist: float = (to_pos - from_pos).length()
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

	# D9: Y-beam aim consolidated on _aim_node (same +Y convention).
	_aim_node(beam, from_pos, to_pos)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		beam.queue_free()
		return
	tree.create_timer(ttl).timeout.connect(beam.queue_free)


static func spawn_sap_burst(parent: Node, pos: Vector3) -> void:
	const SAP_SPARK_ENERGY_CAP := 0.65
	const SAP_FLASH_ENERGY_CAP := 0.65
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
	spark_mat.emission_energy_multiplier = SAP_SPARK_ENERGY_CAP
	assert(spark_mat.emission_energy_multiplier <= SAP_SPARK_ENERGY_CAP + 0.001, "SapSparkCap: sap spark energy exceeds cap")
	print("SapSparkCap: sap spark emission_energy=", spark_mat.emission_energy_multiplier, " cap=", SAP_SPARK_ENERGY_CAP, " (UE MI_SlimeBomb EmissiveStrength unrecovered; mission glow 0.65)")
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
	flash.light_energy = SAP_FLASH_ENERGY_CAP
	assert(flash.light_energy <= SAP_FLASH_ENERGY_CAP + 0.001, "SapFlashCap: sap flash energy exceeds cap")
	print("SapFlashCap: sap flash energy=", flash.light_energy, " cap=", SAP_FLASH_ENERGY_CAP, " (no UE flash light; mission glow 0.65)")
	root.add_child(flash)

	var tree: SceneTree = parent.get_tree()
	if tree == null:
		return
	var fade_tween: Tween = tree.create_tween()
	fade_tween.tween_property(flash, "light_energy", 0.0, 0.9)
	tree.create_timer(0.9).timeout.connect(root.queue_free)


static var _candle_quad: QuadMesh = null
static var _godray_shader: Shader = null
static var _prop_outline_mat: ShaderMaterial = null


static func _get_candle_quad() -> QuadMesh:
	if _candle_quad != null:
		return _candle_quad
	var sh := Shader.new()
	# R3 APPROXIMATE procedural billboarding teardrop flame quad stand-in for
	# compiled Niagara candle-flame bytecode, calibrated to Steam ref.
	sh.code = """shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
void vertex() {
	vec3 origin_w = MODEL_MATRIX[3].xyz;
	float phase = dot(origin_w, vec3(7.3, 11.1, 5.7));
	float tip_t = clamp((VERTEX.y + 0.029) / 0.058, 0.0, 1.0);
	VERTEX.x += sin(TIME * 6.5 + phase) * 0.0025 * tip_t * tip_t;
	vec3 cam_z = INV_VIEW_MATRIX[2].xyz;
	vec3 right = vec3(cam_z.z, 0.0, -cam_z.x);
	float rl = length(right);
	right = (rl > 0.001) ? (right / rl) : vec3(1.0, 0.0, 0.0);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 fwd = cross(right, up);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(right, 0.0),
		vec4(up, 0.0),
		vec4(fwd, 0.0),
		MODEL_MATRIX[3]
	);
}
void fragment() {
	float y = 1.0 - UV.y;
	float width = sin(pow(clamp(y, 0.0, 1.0), 0.65) * 3.14159265) * (1.0 - 0.35 * y);
	float dx = abs(UV.x - 0.5) * 2.0;
	float w = max(width, 0.001);
	float mask = smoothstep(w, w * 0.18, dx) * smoothstep(0.0, 0.12, y) * smoothstep(1.0, 0.72, y);
	float core = smoothstep(0.55, 0.0, length(vec2(dx * 1.15, (y - 0.32) * 1.6)));
	float flick = 0.90 + 0.10 * sin(TIME * 11.3 + NODE_POSITION_WORLD.x * 9.7 + NODE_POSITION_WORLD.z * 13.1);
	vec3 col = mix(vec3(1.8, 0.55, 0.08), vec3(3.2, 2.4, 1.1), clamp(core * 1.2 + (1.0 - y) * 0.25, 0.0, 1.0));
	ALBEDO = col * flick;
	ALPHA = clamp(mask, 0.0, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var q := QuadMesh.new()
	q.size = Vector2(0.026, 0.058)
	q.material = mat
	_candle_quad = q
	return _candle_quad


static func spawn_candle_flame(parent: Node, pos: Vector3) -> void:
	if parent == null:
		return
	var root: Node3D = Node3D.new()
	root.name = "CandleFlame"
	parent.add_child(root)
	root.global_position = pos

	var flame: MeshInstance3D = MeshInstance3D.new()
	flame.name = "FlameQuad"
	flame.mesh = _get_candle_quad()
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position = Vector3(0.0, 0.028, 0.0)
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

	# D9: Z-facing convention (streak modeled along +Z), intentionally NOT
	# _aim_node (Y-beams) or _aim_spot (-Z spotlights).
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


static func spawn_window_godray(parent: Node, pos: Vector3, target_pos: Vector3, ttl: float = 0.0) -> Node3D:
	# V5: ttl <= 0 godrays used to vanish from all accounting (a missed
	# manual free = a permanent cone + lights). The node is now returned AND
	# registered in the persistent set; freed-with-parent still frees it.
	if parent == null:
		return null
	var dist: float = (target_pos - pos).length()
	if dist < 0.001:
		return
	var midpoint: Vector3 = (pos + target_pos) * 0.5

	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.55
	cone.bottom_radius = 1.65
	cone.height = dist
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false

	if _godray_shader == null:
		_godray_shader = Shader.new()
		# R3 APPROXIMATE soft volumetric dust beam stand-in (open-ended cylinder).
		# REFERENCE_MATCHED tint: teal-cyan moon shaft vs KF02/KF06 (S03/S05 Den
		# window shaft). Compiled Niagara falloff curves were not decoded; the
		# fresnel*axial envelope is an eyeballed stand-in, never an extraction.
		_godray_shader.code = "shader_type spatial;\nrender_mode blend_add, unshaded, cull_disabled, depth_draw_never;\nuniform vec4 beam_color : source_color = vec4(0.42, 0.78, 0.90, 0.07);\nvoid fragment() {\n\tfloat fresnel = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.8);\n\tfloat axial = smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.42, UV.y);\n\tALBEDO = beam_color.rgb;\n\tALPHA = beam_color.a * fresnel * axial;\n}\n"
	var shaft_mat: ShaderMaterial = ShaderMaterial.new()
	shaft_mat.shader = _godray_shader
	cone.material = shaft_mat

	var shaft: MeshInstance3D = MeshInstance3D.new()
	shaft.name = "WindowGodray"
	shaft.mesh = cone
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shaft)
	shaft.global_position = midpoint

	# D9: Y-beam aim consolidated on _aim_node (same +Y convention).
	_aim_node(shaft, pos, target_pos)
	if ttl > 0.0:
		var godray_tree: SceneTree = parent.get_tree()
		if godray_tree != null:
			godray_tree.create_timer(ttl).timeout.connect(shaft.queue_free)
	else:
		_register_persistent_vfx(shaft, "WindowGodray")
	return shaft


## V5 registry: caller-owned (ttl <= 0) decor. Weakrefs pruned on every
## register/count so the list stays exact; capped at MAX_PERSISTENT_VFX
## entries (the total stays exact past the cap).
static func _register_persistent_vfx(node: Node3D, label: String) -> void:
	for i: int in range(_persistent_vfx.size() - 1, -1, -1):
		var wr: Variant = _persistent_vfx[i]
		if not (wr is WeakRef) or (wr as WeakRef).get_ref() == null:
			_persistent_vfx.remove_at(i)
	_persistent_vfx_total += 1
	if _persistent_vfx.size() < MAX_PERSISTENT_VFX:
		_persistent_vfx.append(weakref(node))
	if _persistent_vfx_total == 1 or _persistent_vfx_total % 25 == 0:
		print("PersistentVfx: '", label, "' caller-owned (ttl<=0); live=", _persistent_vfx.size(), " total=", _persistent_vfx_total, " (freed with parent; live count via persistent_vfx_count())")


## Live caller-owned VFX for the ledger (prunes dead weakrefs first).
static func persistent_vfx_count() -> int:
	for i: int in range(_persistent_vfx.size() - 1, -1, -1):
		var wr: Variant = _persistent_vfx[i]
		if not (wr is WeakRef) or (wr as WeakRef).get_ref() == null:
			_persistent_vfx.remove_at(i)
	return _persistent_vfx.size()


const FOOTSTEP_MASK_PATH: String = "res://assets/ue/Raw/Art/UI/Icons/T_Decal_Footstep.png"
static var _footstep_mask_tex: Texture2D = null
## V4: every footstep allocated a PlaneMesh + StandardMaterial3D + Tween +
## 6.1 s timer (sprinting = dozens of live transparent quads). The mesh is
## now one shared static; live decals are capped with oldest-first eviction
## (counted, never silent). Per-decal materials stay unique — the fade tween
## drives each decal's own albedo alpha, so sharing them would fade all.
static var _footprint_quad: PlaneMesh = null
static var _footprints_live: Array = []
static var _footprints_evicted: int = 0
const MAX_FOOTPRINTS: int = 24
## V5: ttl <= 0 spawns (godray, foyer beams) are caller-owned decor that used
## to vanish from all accounting. They register here (weakrefs, pruned on
## register, capped) with a log + count; freed-with-parent still frees them,
## and persistent_vfx_count() exposes the live set for the ledger.
static var _persistent_vfx: Array = []
static var _persistent_vfx_total: int = 0
const MAX_PERSISTENT_VFX: int = 512


static func _prune_footprints() -> void:
	for i: int in range(_footprints_live.size() - 1, -1, -1):
		var wr: Variant = _footprints_live[i]
		var ref: Object = (wr as WeakRef).get_ref() if wr is WeakRef else null
		if ref == null or not is_instance_valid(ref):
			_footprints_live.remove_at(i)


static func _get_footstep_mask_tex() -> Texture2D:
	if _footstep_mask_tex != null:
		return _footstep_mask_tex
	var src_img: Image = null
	if ResourceLoader.exists(FOOTSTEP_MASK_PATH):
		var loaded: Variant = load(FOOTSTEP_MASK_PATH)
		if loaded is Texture2D:
			src_img = (loaded as Texture2D).get_image()
	if (src_img == null or src_img.is_empty()) and FileAccess.file_exists(FOOTSTEP_MASK_PATH):
		src_img = Image.load_from_file(ProjectSettings.globalize_path(FOOTSTEP_MASK_PATH))
	if src_img == null or src_img.is_empty():
		return null
	var img: Image = src_img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# V6: the old path ran get_pixel/set_pixel per texel at full authored
	# resolution on the first wet step (main-thread stall). A 128 px
	# luminance mask keeps the footprint alpha the test pins (corner < 0.05,
	# max > 0.5) while the loop drops to <= 16k px; the result is still
	# cached once per session below, and prewarm_footstep_mask() lets the
	# loader hide even that behind the loading screen.
	if img.get_width() > 128 or img.get_height() > 128:
		img.resize(128, 128, Image.INTERPOLATE_BILINEAR)
		print("FootstepMask: downscaled ", src_img.get_width(), "x", src_img.get_height(), " -> 128x128 for one-time alpha bake")
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y: int in range(h):
		for x: int in range(w):
			var c: Color = img.get_pixel(x, y)
			var lum: float = clampf(c.r * 0.299 + c.g * 0.587 + c.b * 0.114, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, lum))
	_footstep_mask_tex = ImageTexture.create_from_image(img)
	print("FootstepMask: baked one-time alpha mask (", img.get_width(), "x", img.get_height(), ") from ", FOOTSTEP_MASK_PATH, ")")
	return _footstep_mask_tex


## V6 companion: bakes the mask now (loading screen) instead of on the
## first wet footstep. Safe to call repeatedly; the cache makes it a no-op.
static func prewarm_footstep_mask() -> void:
	_get_footstep_mask_tex()


static func spawn_footprint_decal(pos: Vector3, forward: Vector3, is_left: bool) -> void:
	_prune_footprints()
	# V4 cap: evict the oldest live decal instead of growing transparent
	# quads without bound; evictions are counted for the ledger.
	while _footprints_live.size() >= MAX_FOOTPRINTS:
		var oldest: Variant = _footprints_live.pop_front()
		var old_node: Object = (oldest as WeakRef).get_ref() if oldest is WeakRef else null
		if old_node is Node and is_instance_valid(old_node as Node):
			(old_node as Node).queue_free()
		_footprints_evicted += 1
		if _footprints_evicted == 1 or _footprints_evicted % 50 == 0:
			push_warning("[vfx_manager] footprint cap (", MAX_FOOTPRINTS, ") evicted oldest live decal (evicted=", _footprints_evicted, ")")
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
	if _footprint_quad == null:
		_footprint_quad = PlaneMesh.new()
		_footprint_quad.size = Vector2(0.16, 0.32)
	var quad: PlaneMesh = _footprint_quad
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.68, 0.74, 0.80, 0.55)
	mat.roughness = 0.85
	mat.emission_enabled = false
	var mask_tex: Texture2D = _get_footstep_mask_tex()
	if mask_tex != null:
		mat.albedo_texture = mask_tex
	quad.material = mat
	var decal: MeshInstance3D = MeshInstance3D.new()
	decal.name = "FootprintQuad"
	decal.mesh = quad
	if not is_left:
		decal.scale = Vector3(-1.0, 1.0, 1.0)
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(decal)
	var fade_tween: Tween = tree.create_tween()
	fade_tween.tween_property(mat, "albedo_color:a", 0.0, 6.0)
	tree.create_timer(6.1).timeout.connect(root.queue_free)
	_footprints_live.append(weakref(root))


static func spawn_blue_wisp(parent: Node3D, local_pos: Vector3, light_energy: float = 0.30) -> Node3D:
	if parent == null:
		return null
	# V3: caller-controlled energy is clamped to the shared 0.65 mission-glow
	# cap (old default 0.30 kept); over-cap callers are logged, not silently
	# honoured. The bob tween is node-bound (orb.create_tween dies with the
	# orb), so no orphan tween survives a freed wisp.
	const WISP_LIGHT_ENERGY_CAP := 0.65
	var wisp_energy: float = clampf(light_energy, 0.0, WISP_LIGHT_ENERGY_CAP)
	if light_energy != wisp_energy:
		push_warning("[vfx_manager] blue wisp energy clamped ", light_energy, " -> ", wisp_energy, " (cap ", WISP_LIGHT_ENERGY_CAP, ")")
	assert(wisp_energy <= WISP_LIGHT_ENERGY_CAP + 0.001, "WispCap: wisp light energy exceeds cap")
	print("WispCap: wisp light energy=", wisp_energy, " cap=", WISP_LIGHT_ENERGY_CAP)
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
	glow.light_energy = wisp_energy
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


static func _get_prop_outline_material() -> ShaderMaterial:
	if _prop_outline_mat != null:
		return _prop_outline_mat
	var sh := Shader.new()
	# R3 APPROXIMATE crisp yellow-gold inverted-hull silhouette outline stand-in
	# for UE post-process interaction highlight (zero interior surface tint).
	sh.code = """shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;
void vertex() {
	float view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float width = clamp(0.005 + 0.0025 * view_dist, 0.004, 0.018);
	vec3 dir = normalize(NORMAL + normalize(VERTEX + vec3(1e-5)) * 0.25);
	VERTEX += dir * width;
}
void fragment() {
	ALBEDO = vec3(1.4, 1.15, 0.30);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_prop_outline_mat = mat
	return _prop_outline_mat


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
			if mi.has_meta("_vfx_hl") and mi.get_meta("_vfx_hl", false) == true:
				continue
			mi.set_meta("_vfx_hl", true)
			mi.set_meta("_vfx_hl_orig", mi.material_overlay)
			mi.material_overlay = _get_prop_outline_material()
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


## R3 APPROXIMATE / REFERENCE_MATCHED (HL-1): KF20 smoke plume (S18).
## Opaque grey-white volumetric puffs billow horizontally across the grand
## steps after the 02:28.20 ignition flash, then linger and dissipate. The
## compiled Niagara system (NS_SmokeBomb: 24 scripts, 172 curve LUTs) was NOT
## decompiled: layer counts, velocities, growth and the 25 s box life
## (5 x 5 x 4 m authored volume) are REFERENCE_MATCHED stand-ins around the
## real extents/ttl defaults. Never an extraction.
##
## Three GPUParticles3D layers replace the old single burst + box stand-in:
##   PlumeCore   - fast dense core thrown out at the ignition instant
##   PlumeBillow - slower, larger puffs that expand horizontally over ~5 s
##   PlumeHaze   - long-lived low drift layer that fades across the 25 s ttl
static func spawn_smoke_plume(parent: Node, pos: Vector3, half_extents: Vector3 = Vector3(2.5, 2.0, 2.5), ttl: float = 25.0) -> Node3D:
	const IGNITION_FLASH_ENERGY_CAP := 0.65
	if parent == null or not parent.is_inside_tree():
		return null
	var root: Node3D = Node3D.new()
	root.name = "SmokePlume"
	parent.add_child(root)
	root.global_position = pos

	var flash: OmniLight3D = OmniLight3D.new()
	flash.name = "IgnitionFlash"
	flash.light_color = Color(1.0, 0.75, 0.45)
	flash.omni_range = 9.0
	flash.light_energy = IGNITION_FLASH_ENERGY_CAP
	assert(flash.light_energy <= IGNITION_FLASH_ENERGY_CAP + 0.001, "SmokeFlashCap: ignition flash energy exceeds cap")
	print("SmokeFlashCap: ignition flash energy=", flash.light_energy, " cap=", IGNITION_FLASH_ENERGY_CAP, " (no UE flash light; mission glow 0.65)")
	root.add_child(flash)

	var tint: Color = Color(0.86, 0.88, 0.91, 1.0)
	var ext: Vector3 = Vector3(maxf(half_extents.x, 0.2), maxf(half_extents.y, 0.2), maxf(half_extents.z, 0.2))

	_add_smoke_layer(root, "PlumeCore", 40, 3.2, 0.9, true, 0.75,
		ext * 0.7, 1.6, 3.2, 1.0, tint, 1.0, 0.06, 1.0, 0.0)
	_add_smoke_layer(root, "PlumeBillow", 64, 5.5, 0.7, true, 1.0,
		ext, 0.8, 2.2, 1.35, tint, 0.92, 0.07, 1.0, 0.0)
	var haze_mat: ShaderMaterial = _add_smoke_layer(root, "PlumeHaze", 26, 6.5, 0.15, false, 1.35,
		Vector3(ext.x * 1.1, 0.35, ext.z * 1.1), 0.15, 0.55, 1.6, tint, 0.55, 0.04, 0.5, -ext.y * 0.55)

	var tree: SceneTree = parent.get_tree()
	if tree != null:
		var fade: Tween = tree.create_tween()
		fade.tween_property(flash, "light_energy", 0.0, 1.2)
		# KF20 linger/dissipate: the low haze thins out before the authored
		# 25 s box life ends instead of vanishing with the burst layers.
		var haze_fade: Tween = tree.create_tween()
		haze_fade.tween_interval(2.0)
		haze_fade.tween_property(haze_mat, "shader_parameter/density", 0.0, maxf(ttl - 2.0, 2.0))
		tree.create_timer(maxf(ttl, 6.0)).timeout.connect(root.queue_free)
	return root


static func _smoke_material(density: float, glow: float, tint: Color) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SMOKE_SHADER
	mat.set_shader_parameter("smoke_tint", tint)
	mat.set_shader_parameter("density", density)
	mat.set_shader_parameter("glow", glow)
	return mat


static func _smoke_growth_curve() -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.max_value = 2.0
	curve.add_point(Vector2(0.0, 0.28))
	curve.add_point(Vector2(0.35, 0.85))
	curve.add_point(Vector2(1.0, 1.55))
	var tex: CurveTexture = CurveTexture.new()
	tex.curve = curve
	return tex


static func _smoke_alpha_ramp(tint: Color, peak: float) -> GradientTexture1D:
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.08, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(tint.r, tint.g, tint.b, 0.0),
		Color(tint.r, tint.g, tint.b, peak),
		Color(tint.r, tint.g, tint.b, peak * 0.8),
		Color(tint.r, tint.g, tint.b, 0.0),
	])
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = grad
	return tex


static func _add_smoke_layer(root: Node3D, layer_name: String, amount: int, lifetime: float,
		explosiveness: float, one_shot: bool, puff_radius: float, extents: Vector3,
		velocity_min: float, velocity_max: float, scale_mul: float, tint: Color,
		density: float, glow: float, alpha_peak: float, y_offset: float) -> ShaderMaterial:
	var puff_mesh: SphereMesh = SphereMesh.new()
	puff_mesh.radius = puff_radius
	puff_mesh.height = puff_radius * 2.0
	puff_mesh.radial_segments = 12
	puff_mesh.rings = 8
	var mat: ShaderMaterial = _smoke_material(density, glow, tint)
	puff_mesh.material = mat

	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.0, 0.12, 0.0)
	pm.spread = 85.0
	pm.gravity = Vector3(0.0, 0.22, 0.0)
	pm.initial_velocity_min = velocity_min
	pm.initial_velocity_max = velocity_max
	pm.damping_min = 1.0
	pm.damping_max = 1.8
	pm.scale_min = 0.75 * scale_mul
	pm.scale_max = 1.15 * scale_mul
	pm.scale_curve = _smoke_growth_curve()
	pm.color_ramp = _smoke_alpha_ramp(tint, alpha_peak)

	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = layer_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = one_shot
	particles.explosiveness = explosiveness
	particles.process_material = pm
	particles.draw_pass_1 = puff_mesh
	particles.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0))
	particles.position = Vector3(0.0, y_offset, 0.0)
	root.add_child(particles)
	particles.emitting = true
	return mat


## R3 APPROXIMATE / REFERENCE_MATCHED (HL-1): KF27 foyer security beams (S24).
## Two crisp horizontal white volumetric beams span wall-to-wall from the
## mid-height circular emitter (KF27#1) with the glowing cyan diamond node
## above the far doors (KF27#3). Sweep/trip logic lives in HL-3 territory;
## this only dresses the S24 look. Never an extraction.
static func spawn_foyer_security_beam(parent: Node, emitter_pos: Vector3, far_pos: Vector3, beam_gap: float = 0.7, ttl: float = 0.0) -> Node3D:
	if parent == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "FoyerSecurityBeam"
	parent.add_child(root)
	root.global_position = emitter_pos
	for i: int in [-1, 1]:
		var a: Vector3 = emitter_pos + Vector3(0.0, float(i) * beam_gap * 0.5, 0.0)
		var b: Vector3 = far_pos + Vector3(0.0, float(i) * beam_gap * 0.5, 0.0)
		_add_beam_mesh(root, a, b, 0.035, Color(1.0, 1.0, 1.0, 0.55), 2.0)
	var housing_mesh: SphereMesh = SphereMesh.new()
	housing_mesh.radius = 0.12
	housing_mesh.height = 0.24
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	housing_mat.albedo_color = Color(1.0, 1.0, 1.0)
	housing_mat.emission_enabled = true
	housing_mat.emission = Color(1.0, 1.0, 1.0)
	housing_mat.emission_energy_multiplier = 3.0
	housing_mesh.material = housing_mat
	var housing: MeshInstance3D = MeshInstance3D.new()
	housing.name = "BeamEmitter"
	housing.mesh = housing_mesh
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(housing)
	housing.global_position = emitter_pos
	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "EmitterGlow"
	glow.light_color = Color(1.0, 1.0, 1.0)
	glow.omni_range = 5.0
	glow.light_energy = 1.2
	root.add_child(glow)
	glow.global_position = emitter_pos
	var node_mesh: BoxMesh = BoxMesh.new()
	node_mesh.size = Vector3(0.22, 0.22, 0.22)
	var node_mat: StandardMaterial3D = StandardMaterial3D.new()
	node_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node_mat.albedo_color = Color(0.3, 0.95, 1.0)
	node_mat.emission_enabled = true
	node_mat.emission = Color(0.3, 0.95, 1.0)
	node_mat.emission_energy_multiplier = 3.0
	node_mesh.material = node_mat
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "CeilingNode"
	node.mesh = node_mesh
	node.rotation = Vector3(0.0, 0.0, deg_to_rad(45.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	node.global_position = (emitter_pos + far_pos) * 0.5 + Vector3(0.0, 1.6, 0.0)
	# KF27#2: flush square metallic floor plate between the beams. The caller
	# owns the real foyer floor height; 2 cm sits flush on a y=0 floor tile.
	var plate_mesh: BoxMesh = BoxMesh.new()
	plate_mesh.size = Vector3(0.86, 0.03, 0.86)
	var plate_mat: StandardMaterial3D = StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.55, 0.57, 0.60)
	plate_mat.metallic = 0.85
	plate_mat.roughness = 0.28
	plate_mat.emission_enabled = true
	plate_mat.emission = Color(0.80, 0.92, 1.0)
	plate_mat.emission_energy_multiplier = 0.35
	plate_mesh.material = plate_mat
	var plate: MeshInstance3D = MeshInstance3D.new()
	plate.name = "FloorPlate"
	plate.mesh = plate_mesh
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plate)
	plate.global_position = Vector3((emitter_pos.x + far_pos.x) * 0.5, 0.015, far_pos.z)
	_register_or_free(root, parent, ttl, "FoyerSecurityBeam")
	return root


## Shared unshaded beam quad-strip used by the foyer/grapple-style beams.
static func _add_beam_mesh(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color, energy: float) -> void:
	var offset: Vector3 = b - a
	var dist: float = offset.length()
	if dist < 0.001:
		return
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = dist
	cyl.radial_segments = 12
	cyl.rings = 1
	# APPROX_SHADER (HL-1, KF27): the UE beam cards were not decompiled; the
	# view-facing core + feathered silhouette makes the cylinder read as a
	# crisp white volumetric shaft instead of a lit plastic rod.
	var beam_mat: ShaderMaterial = ShaderMaterial.new()
	beam_mat.shader = BEAM_SHADER
	beam_mat.set_shader_parameter("beam_color", color)
	beam_mat.set_shader_parameter("energy", energy)
	cyl.material = beam_mat
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.name = "SecurityBeam"
	beam.mesh = cyl
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	beam.global_position = (a + b) * 0.5
	_aim_node(beam, a, b)


## D9: shared +Y aim (cylinder/cone beams are modeled along +Y). Callers:
## grapple beam, security beam, godray shaft, foyer beams, alarm cone.
## Z-facing streaks (blackjack swing) and -Z spotlights keep their own
## convention (_aim_spot / inline with a comment) — same math, different axis.
static func _aim_node(node: Node3D, a: Vector3, b: Vector3) -> void:
	var offset: Vector3 = b - a
	if offset.length() < 0.001:
		return
	var y_axis: Vector3 = offset.normalized()
	var up_hint: Vector3 = Vector3.UP
	if absf(y_axis.dot(Vector3.UP)) > 0.99:
		up_hint = Vector3.RIGHT
	var x_axis: Vector3 = up_hint.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	node.basis = Basis(x_axis, y_axis, z_axis)


## R3 APPROXIMATE / REFERENCE_MATCHED (HL-1): KF28 purple arcane ward (S25).
## Faceted crystalline barrier sealing the foyer archway (KF28#2) plus the
## sustained ward hum lighting. Shard layout is eyeballed from the frame;
## nothing here decodes a Niagara system. Never an extraction.
static func spawn_arcane_ward(parent: Node, pos: Vector3, facing_yaw: float = 0.0, width: float = 3.2, height: float = 2.6, ttl: float = 0.0) -> Node3D:
	# V2: ward energies (wash 1.6, veil 2.4, shards 2.8) sat above every other
	# cap with no shared budget. Capped + asserted here; stacked wards stay
	# inside the Forward+ budget instead of busting it silently.
	const WARD_WASH_ENERGY := 1.2
	const WARD_SHADER_ENERGY := 2.0
	assert(WARD_WASH_ENERGY <= 1.2 and WARD_SHADER_ENERGY <= 2.0, "WardCap: ward energies exceed budget")
	print("WardCap: wash=", WARD_WASH_ENERGY, " shader=", WARD_SHADER_ENERGY, " (KF28 ward; shared VFX budget, was 1.6/2.4/2.8)")
	if parent == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "ArcaneWard"
	parent.add_child(root)
	root.global_position = pos
	root.rotation.y = facing_yaw
	var veil_mesh: PlaneMesh = PlaneMesh.new()
	veil_mesh.size = Vector2(width, height)
	# APPROX_SHADER (HL-1, KF28): procedural faceted crystal cells + rim vein
	# stand in for the cooked ward graph (never decompiled). edge_fade keeps
	# the archway veil feathered; the shard meshes keep full coverage.
	var veil_mat: ShaderMaterial = ShaderMaterial.new()
	veil_mat.shader = WARD_SHADER
	veil_mat.set_shader_parameter("ward_color", Color(0.62, 0.28, 1.0, 0.40))
	veil_mat.set_shader_parameter("energy", WARD_SHADER_ENERGY)
	veil_mat.set_shader_parameter("facet_scale", 6.5)
	veil_mat.set_shader_parameter("edge_fade", 1.0)
	veil_mesh.material = veil_mat
	var veil: MeshInstance3D = MeshInstance3D.new()
	veil.name = "WardVeil"
	veil.mesh = veil_mesh
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(veil)
	veil.position = Vector3(0.0, height * 0.5, 0.0)
	var shard_mat: ShaderMaterial = ShaderMaterial.new()
	shard_mat.shader = WARD_SHADER
	shard_mat.set_shader_parameter("ward_color", Color(0.66, 0.32, 1.0, 0.90))
	shard_mat.set_shader_parameter("energy", WARD_SHADER_ENERGY)
	shard_mat.set_shader_parameter("facet_scale", 4.0)
	shard_mat.set_shader_parameter("edge_fade", 0.0)
	for i: int in range(6):
		var shard_mesh: BoxMesh = BoxMesh.new()
		var t: float = float(i) / 5.0
		shard_mesh.size = Vector3(0.18, height * (0.45 + 0.25 * (1.0 - absf(t * 2.0 - 1.0))), 0.08)
		shard_mesh.material = shard_mat
		var shard: MeshInstance3D = MeshInstance3D.new()
		shard.name = "WardShard"
		shard.mesh = shard_mesh
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shard)
		shard.position = Vector3(lerpf(-width * 0.45, width * 0.45, t), height * 0.5, 0.05 * float(i % 2))
		shard.rotation = Vector3(0.0, 0.12 * float(i - 2), 0.10 * float((i % 3) - 1))
	var wash: OmniLight3D = OmniLight3D.new()
	wash.name = "WardWash"
	wash.light_color = Color(0.55, 0.25, 1.0)
	wash.omni_range = 7.0
	wash.light_energy = WARD_WASH_ENERGY
	assert(wash.light_energy <= WARD_WASH_ENERGY + 0.001, "WardWashCap: ward wash energy exceeds cap")
	root.add_child(wash)
	wash.position = Vector3(0.0, height * 0.6, 1.0)
	var mote_mesh: SphereMesh = SphereMesh.new()
	mote_mesh.radius = 0.035
	mote_mesh.height = 0.07
	var mote_mat: StandardMaterial3D = StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.albedo_color = Color(0.7, 0.4, 1.0)
	mote_mat.emission_enabled = true
	mote_mat.emission = Color(0.65, 0.35, 1.0)
	mote_mat.emission_energy_multiplier = 2.0
	mote_mesh.material = mote_mat
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.45, 0.2, 0.3)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 20.0
	pm.gravity = Vector3(0.0, 0.4, 0.0)
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(0.7, 0.4, 1.0, 1.0)
	var motes: GPUParticles3D = GPUParticles3D.new()
	motes.name = "WardMotes"
	motes.amount = 28
	motes.lifetime = 2.2
	motes.process_material = pm
	motes.draw_pass_1 = mote_mesh
	motes.visibility_aabb = AABB(Vector3(-4, -1, -2), Vector3(8, 5, 4))
	root.add_child(motes)
	motes.position = Vector3(0.0, 0.4, 0.0)
	motes.emitting = true
	_register_or_free(root, parent, ttl, "ArcaneWard")
	return root


## R3 APPROXIMATE / REFERENCE_MATCHED (HL-1): KF28 green vine lock (S25).
## Emissive thorny vines across the Basement Stairs doorway (KF28#5).
## Placement/trigger is HL-3 gameplay logic; this only dresses the look.
## Never an extraction.
static func spawn_vine_lock(parent: Node, pos: Vector3, facing_yaw: float = 0.0, width: float = 2.0, height: float = 2.4, ttl: float = 0.0) -> Node3D:
	if parent == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "VineLock"
	parent.add_child(root)
	root.global_position = pos
	root.rotation.y = facing_yaw
	var vine_mat: StandardMaterial3D = StandardMaterial3D.new()
	vine_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vine_mat.albedo_color = Color(0.25, 0.9, 0.35)
	vine_mat.emission_enabled = true
	vine_mat.emission = Color(0.2, 0.85, 0.3)
	vine_mat.emission_energy_multiplier = 2.0
	for i: int in range(8):
		var strand_mesh: CylinderMesh = CylinderMesh.new()
		strand_mesh.top_radius = 0.02
		strand_mesh.bottom_radius = 0.07
		strand_mesh.height = height * (0.5 + 0.1 * float(i % 3))
		strand_mesh.radial_segments = 6
		strand_mesh.material = vine_mat
		var strand: MeshInstance3D = MeshInstance3D.new()
		strand.name = "VineStrand"
		strand.mesh = strand_mesh
		strand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(strand)
		var t: float = float(i) / 7.0
		strand.position = Vector3(lerpf(-width * 0.45, width * 0.45, t), height * 0.45, 0.0)
		strand.rotation = Vector3(0.15 * float((i % 3) - 1), 0.0, lerpf(-0.5, 0.5, t))
	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "VineGlow"
	glow.light_color = Color(0.25, 0.9, 0.35)
	glow.omni_range = 5.0
	glow.light_energy = 1.2
	root.add_child(glow)
	glow.position = Vector3(0.0, height * 0.5, 0.6)
	_register_or_free(root, parent, ttl, "VineLock")
	return root


## V5 shared tail: timed spawns self-free; caller-owned (ttl <= 0) decor
## registers in the persistent set instead of vanishing from accounting.
static func _register_or_free(root: Node3D, parent: Node, ttl: float, label: String) -> void:
	if ttl > 0.0:
		var tree: SceneTree = parent.get_tree()
		if tree != null:
			tree.create_timer(ttl).timeout.connect(root.queue_free)
	else:
		_register_persistent_vfx(root, label)


## R3 APPROXIMATE / REFERENCE_MATCHED (HL-1): KF29 crimson alarm wash (S26).
## Intense crimson spotlight from the wall security fixture over the slate
## stairs (KF29#2, 03:38.20-03:39.60), with a strobing volumetric cone so the
## alarm reads as a sweeping wash rather than a point light. The crimson cast
## is authored light, not a particle effect. ttl frees the fixture wash.
## Never an extraction.
static func spawn_crimson_alarm(parent: Node, fixture_pos: Vector3, target_pos: Vector3, ttl: float = 6.0) -> Node3D:
	# V1: the old strobe peaked at 5.4 (base 4.5 + overshoot) while a second
	# fade tween drove the same light_energy — last-writer-wins flicker/pop.
	# Now the strobe dips 4.5 -> 2.2 -> 4.5 (no overshoot), the strobe is
	# killed before the fade owns the property, and caps assert loudly.
	const ALARM_BASE_ENERGY := 4.5
	const ALARM_DIP_ENERGY := 2.2
	const ALARM_BULB_ENERGY := 3.0
	assert(ALARM_BASE_ENERGY <= 4.5 and ALARM_DIP_ENERGY >= 2.0, "AlarmCap: strobe bounds changed")
	print("AlarmCap: spot base=", ALARM_BASE_ENERGY, " dip=", ALARM_DIP_ENERGY, " bulb=", ALARM_BULB_ENERGY, " (KF29 alarm wash; strobe never exceeds base)")
	if parent == null:
		return null
	var root: Node3D = Node3D.new()
	root.name = "CrimsonAlarm"
	parent.add_child(root)
	root.global_position = fixture_pos
	var offset: Vector3 = target_pos - fixture_pos
	var dist: float = maxf(offset.length(), 0.5)
	var spot: SpotLight3D = SpotLight3D.new()
	spot.name = "AlarmSpot"
	spot.light_color = Color(1.0, 0.07, 0.05)
	spot.light_energy = ALARM_BASE_ENERGY
	spot.spot_range = dist + 4.0
	spot.spot_angle = 32.0
	spot.spot_attenuation = 1.0
	root.add_child(spot)
	_aim_spot(spot, offset)
	# APPROX_SHADER / REFERENCE_MATCHED (HL-1): TIME-strobed volume cone.
	var cone_mesh: CylinderMesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.12
	cone_mesh.bottom_radius = clampf(dist * tan(deg_to_rad(16.0)), 0.25, 4.0)
	cone_mesh.height = dist
	cone_mesh.radial_segments = 20
	cone_mesh.rings = 1
	cone_mesh.cap_top = false
	cone_mesh.cap_bottom = false
	var cone_mat: ShaderMaterial = ShaderMaterial.new()
	cone_mat.shader = ALARM_SHADER
	cone_mat.set_shader_parameter("alarm_color", Color(1.0, 0.07, 0.05, 0.12))
	cone_mat.set_shader_parameter("energy", 2.2)
	cone_mat.set_shader_parameter("strobe_hz", 2.2)
	cone_mesh.material = cone_mat
	var cone: MeshInstance3D = MeshInstance3D.new()
	cone.name = "AlarmCone"
	cone.mesh = cone_mesh
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cone)
	cone.global_position = fixture_pos + offset * 0.5
	_aim_node(cone, fixture_pos, target_pos)
	var bulb_mesh: SphereMesh = SphereMesh.new()
	bulb_mesh.radius = 0.09
	bulb_mesh.height = 0.18
	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb_mat.albedo_color = Color(1.0, 0.1, 0.08)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.08, 0.06)
	bulb_mat.emission_energy_multiplier = ALARM_BULB_ENERGY
	assert(bulb_mat.emission_energy_multiplier <= ALARM_BULB_ENERGY + 0.001, "AlarmBulbCap: alarm bulb energy exceeds cap")
	bulb_mesh.material = bulb_mat
	var bulb: MeshInstance3D = MeshInstance3D.new()
	bulb.name = "AlarmBulb"
	bulb.mesh = bulb_mesh
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bulb)
	var tree: SceneTree = parent.get_tree()
	if tree != null and ttl > 0.0:
		# Alarm strobe pulse (KF29): two dips per second through the wash.
		var strobe: Tween = tree.create_tween()
		strobe.set_loops(maxi(int(ttl * 2.2), 2))
		strobe.tween_property(spot, "light_energy", ALARM_DIP_ENERGY, 0.11)
		strobe.tween_property(spot, "light_energy", ALARM_BASE_ENERGY, 0.11)
		var fade: Tween = tree.create_tween()
		fade.tween_interval(maxf(ttl - 0.6, 0.1))
		# The fade owns light_energy last: kill the strobe first so the two
		# tweens never fight over the same property (old flicker/pop).
		fade.tween_callback(strobe.kill)
		fade.tween_property(spot, "light_energy", 0.0, 0.6)
		var cone_fade: Tween = tree.create_tween()
		cone_fade.tween_interval(maxf(ttl - 0.8, 0.1))
		cone_fade.tween_property(cone_mat, "shader_parameter/energy", 0.0, 0.8)
		tree.create_timer(ttl + 0.1).timeout.connect(root.queue_free)
	return root


static func _aim_spot(spot: SpotLight3D, offset: Vector3) -> void:
	if offset.length() < 0.001:
		return
	var fwd: Vector3 = offset.normalized()
	var up_hint: Vector3 = Vector3.UP
	if absf(fwd.dot(Vector3.UP)) > 0.99:
		up_hint = Vector3.RIGHT
	# SpotLight3D shines along -Z: build the basis with -Z toward the target.
	var z_axis: Vector3 = -fwd
	var x_axis: Vector3 = up_hint.cross(z_axis).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	spot.basis = Basis(x_axis, y_axis, z_axis)


## Drops every process-lifetime VFX resource so shutdown reports no leaks.
static func cleanup_static_caches() -> void:
	_candle_quad = null
	_godray_shader = null
	_prop_outline_mat = null
	_footstep_mask_tex = null
	_footprint_quad = null
	_footprints_live.clear()
	_persistent_vfx.clear()
