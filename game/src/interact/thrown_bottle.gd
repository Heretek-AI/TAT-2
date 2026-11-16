extends RigidBody3D
## Thrown distraction bottle. Spawned by the player via secondary_action when
## a bottle charge is held; on first impact it emits a loud noise so guards
## investigate, then frees itself.
##
## Documented approximations (the cooked projectile carries no InitialSpeed
## and no impact-noise value):
##   THROW_SPEED_M_S = 12.0 m/s initial velocity along the throw direction.
##   IMPACT_NOISE_M  = 10.0 m NoiseBus radius with the "bottle" tag.

const THROW_SPEED_M_S: float = 12.0 # APPROXIMATION: no UE InitialSpeed source
const IMPACT_NOISE_M: float = 10.0 # APPROXIMATION: no UE impact-noise source
const BOTTLE_MESHES: Array[String] = [
	"res://assets/ue/Content/Art/Environment/Props/Dining/Food/Wine/SM_BottleWineB.glb",
	"res://assets/ue/Content/Art/Environment/Props/Dining/Food/Wine/SM_BottleWineA.glb",
]

var thrower: Node = null
var _impacted: bool = false


## Throws a bottle from origin along direction. Returns the bottle node.
static func throw_from(parent: Node, origin: Vector3, direction: Vector3, p_thrower: Node) -> Node:
	var Script := load("res://src/interact/thrown_bottle.gd") as GDScript
	var bottle: RigidBody3D = Script.new()
	bottle.thrower = p_thrower
	parent.add_child(bottle)
	bottle.global_position = origin
	var dir: Vector3 = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	bottle.linear_velocity = dir * THROW_SPEED_M_S
	bottle.angular_velocity = Vector3(6.0, 2.0, 4.0)
	return bottle


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 1
	mass = 0.4
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.25
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.07
	col.shape = sph
	add_child(col)
	for mesh_path in BOTTLE_MESHES:
		if ResourceLoader.exists(mesh_path):
			var packed := ResourceLoader.load(mesh_path) as PackedScene
			if packed == null:
				continue
			var inst := packed.instantiate() as Node3D
			if inst != null:
				inst.scale = Vector3.ONE * 1.0
				add_child(inst)
				break
	body_entered.connect(_on_body_entered)
	# Failsafe: a bottle that never impacts still despawns.
	get_tree().create_timer(6.0).timeout.connect(_on_expire)


func _on_body_entered(_body: Node) -> void:
	_impact()


func _on_expire() -> void:
	if not _impacted:
		_impact()


func _impact() -> void:
	if _impacted:
		return
	_impacted = true
	if thrower != null and is_instance_valid(thrower):
		NoiseBus.emit_noise(global_position, IMPACT_NOISE_M, thrower, "bottle")
	else:
		NoiseBus.emit_noise(global_position, IMPACT_NOISE_M, self, "bottle")
	queue_free()
