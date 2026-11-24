extends RigidBody3D
## Ballistic Smoke Bomb projectile.
## Authored constants from BP_Projectile_SmokeBomb.json:
##   InitialSpeed = 3000.0 cm/s -> 30.0 m/s
##   Bounciness   = 0.064
##   Friction     = 1.0
##   DestroySeconds = 0.5 s (delay after impact before cloud detonation)
##   BP_SmokeBomb_WorldActor.InitialLifeSpan = 25.0 s

const VfxManager = preload("res://src/core/vfx_manager.gd")

const INITIAL_SPEED_M_S: float = 30.0
const BOUNCINESS: float = 0.064
const FRICTION: float = 1.0
const DETONATE_DELAY_S: float = 0.5
const SMOKE_TTL_S: float = 25.0
const FAILSAFE_LIFETIME_S: float = 6.0
const SMOKE_MESH_PATH: String = "res://assets/ue/Content/Art/Gameplay/Gear/SmokeBomb/SM_Bomb_Smoke.glb"
const SMOKE_TEX_D: String = "res://assets/ue/Raw/Art/Gameplay/Gear/SmokeBomb/T_SmokeBomb_D.png"
const SMOKE_TEX_N: String = "res://assets/ue/Raw/Art/Gameplay/Gear/SmokeBomb/T_SmokeBomb_N.png"
const SMOKE_TEX_ORM: String = "res://assets/ue/Raw/Art/Gameplay/Gear/SmokeBomb/T_SmokeBomb_ORM.png"

var thrower: Node = null
var level_ctrl: Node = null
var _impact_started: bool = false
var _detonated: bool = false


static func throw_from(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	p_thrower: Node,
	p_level_ctrl: Node = null
) -> RigidBody3D:
	var ScriptRes := load("res://src/player/smoke_projectile.gd") as GDScript
	var proj := ScriptRes.new() as RigidBody3D
	proj.thrower = p_thrower
	proj.level_ctrl = p_level_ctrl
	if parent != null:
		parent.add_child(proj)
	if proj.is_inside_tree():
		proj.global_position = origin
	else:
		proj.position = origin
	var dir: Vector3 = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	proj.linear_velocity = dir * INITIAL_SPEED_M_S
	proj.angular_velocity = Vector3(6.0, 2.0, 4.0)
	# S18: smoke-bomb equip/throw foley (real Wwise Eqp_SmokeBomb_Cast).
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var am: Node = (loop as SceneTree).root.get_node_or_null("AudioManager")
		if am != null and am.has_method("play_cue"):
			am.call("play_cue", "smoke_cast", origin)
	return proj


func _ready() -> void:
	name = "SmokeProjectile"
	collision_layer = 0
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 1
	continuous_cd = true
	mass = 0.5
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = BOUNCINESS
	physics_material_override.friction = FRICTION

	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.08
	col.shape = sph
	add_child(col)

	var added_mesh := false
	if ResourceLoader.exists(SMOKE_MESH_PATH):
		var packed := ResourceLoader.load(SMOKE_MESH_PATH) as PackedScene
		if packed != null:
			var inst := packed.instantiate() as Node3D
			if inst != null:
				inst.scale = Vector3.ONE
				_apply_smoke_mat(inst)
				add_child(inst)
				added_mesh = true
	if not added_mesh:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.055
		sm.height = 0.11
		var fallback_mat := StandardMaterial3D.new()
		fallback_mat.albedo_color = Color(0.14, 0.16, 0.14)
		fallback_mat.roughness = 0.7
		sm.material = fallback_mat
		mi.mesh = sm
		add_child(mi)

	body_entered.connect(_on_body_entered)
	var tree := get_tree()
	if tree != null:
		tree.create_timer(FAILSAFE_LIFETIME_S).timeout.connect(_on_failsafe_timeout)


func _apply_smoke_mat(root_node: Node) -> void:
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(SMOKE_TEX_D):
		mat.albedo_texture = ResourceLoader.load(SMOKE_TEX_D) as Texture2D
	if ResourceLoader.exists(SMOKE_TEX_N):
		mat.normal_enabled = true
		mat.normal_texture = ResourceLoader.load(SMOKE_TEX_N) as Texture2D
	if ResourceLoader.exists(SMOKE_TEX_ORM):
		var orm := ResourceLoader.load(SMOKE_TEX_ORM) as Texture2D
		if orm != null:
			mat.ao_enabled = true
			mat.ao_texture = orm
			mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			mat.roughness_texture = orm
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			mat.metallic = 1.0
			mat.metallic_texture = orm
			mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(s, mat)


func _on_body_entered(_body: Node) -> void:
	if _impact_started or _detonated:
		return
	_impact_started = true
	var tree := get_tree()
	if tree != null:
		tree.create_timer(DETONATE_DELAY_S).timeout.connect(_detonate)
	else:
		_detonate()


func _on_failsafe_timeout() -> void:
	if not _detonated:
		_detonate()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	var parent_node: Node = get_parent()
	if level_ctrl != null and is_instance_valid(level_ctrl) and level_ctrl.has_method("spawn_smoke"):
		level_ctrl.call("spawn_smoke", global_position, SMOKE_TTL_S)
	elif parent_node != null and parent_node.is_inside_tree():
		VfxManager.spawn_smoke_cloud(parent_node, global_position, Vector3(2.5, 2.0, 2.5), SMOKE_TTL_S)
	var nb: Node = get_node_or_null("/root/NoiseBus")
	if nb != null and nb.has_method("emit_noise"):
		var src: Node = thrower if (thrower != null and is_instance_valid(thrower)) else self
		nb.call("emit_noise", global_position, 7.0, src, "smoke")
	# S18: sustained pressurized hiss layer over the detonation pop. W5D: the
	# pin is an Alive_Loop; give it the cloud's TTL so the handle ends with the
	# smoke instead of hissing forever.
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_cue"):
		am.call("play_cue", "smoke_cloud", global_position, SMOKE_TTL_S)
	queue_free()
