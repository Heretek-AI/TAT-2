extends Area3D
## Authored security-turret projectile (BP_Projectile_SecurityTurret_C).
##
## Family metric: 40 m/s max speed, 10 damage, 30 s life. Motion is a per-frame
## raycast from the previous position, which prevents tunnelling at 40 m/s
## (0.67 m per 60 Hz frame) without relying on a thin area overlap. Any world
## body ends the projectile; only the player takes the authored damage.

const Geometry := preload("res://src/devices/device_geometry.gd")

var speed_m_s: float = 40.0
var damage_amount: float = 10.0
var life_seconds: float = 30.0
var direction: Vector3 = Vector3.RIGHT
var shooter: Node = null

var _ttl: float = 30.0
var _done: bool = false
var _built: bool = false


func configure(origin: Vector3, dir: Vector3, speed: float, damage: float, life: float, source: Node = null) -> void:
	# configure() runs before add_child() in the turret, so only local
	# position is safe here; the turret applies global_position after adding.
	position = origin
	direction = dir.normalized() if dir.length_squared() > 0.000001 else Vector3.RIGHT
	speed_m_s = speed
	damage_amount = damage
	life_seconds = life
	_ttl = life
	shooter = source
	_build()


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	collision_layer = 0
	collision_mask = 1 | 2 | 4 | 8
	monitorable = false
	# Motion is raycast-based; an overlap area is not needed and would add a
	# second, tunnelling-prone collision path.
	monitoring = false
	var shape_node := CollisionShape3D.new()
	shape_node.name = "ProjectileShape"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	shape_node.shape = sphere
	add_child(shape_node)
	var mesh := MeshInstance3D.new()
	mesh.name = "ProjectileVisual"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.07
	sphere_mesh.height = 0.14
	sphere_mesh.radial_segments = 6
	sphere_mesh.rings = 3
	mesh.mesh = sphere_mesh
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_ttl -= delta
	if _ttl <= 0.0:
		queue_free()
		return
	var from: Vector3 = global_position
	var to: Vector3 = from + direction * speed_m_s * delta
	var mask: int = 1 | 2 | 4 | 8
	if is_inside_tree():
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var exclusions: Array[RID] = [get_rid()]
		if is_instance_valid(shooter) and shooter is CollisionObject3D:
			exclusions.append((shooter as CollisionObject3D).get_rid())
		var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclusions)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			var body_v: Variant = hit.get("collider")
			if body_v is Node:
				_impact(body_v as Node)
				return
	global_position = to


## Test seam and shared impact path. Returns true when the projectile consumed
## its hit (world, guard or player); the caller never needs the physics frame.
func _impact(body: Node) -> bool:
	if body == null or body == self:
		return false
	if is_instance_valid(shooter) and body == shooter:
		return false
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.call("take_damage", damage_amount)
	_done = true
	queue_free()
	return true


func remaining_life() -> float:
	return _ttl
