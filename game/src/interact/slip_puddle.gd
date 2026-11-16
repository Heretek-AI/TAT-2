extends Area3D
## MagicSlime (Slithersap) puddle + inhibitor.
##
## Real UE sources (see docs/reports/tool-mechanics.md):
## - BP_MagicSlime_Tool MaxAmmo 4
## - BP_MagicSlime_ExplodingProjectile: Puddle Radius 200 cm, explosion delay 0,
##   InhibitableActorSearchRadius 150 cm, Inhibitor Class BP_MagicSlime_Inhibitor_C
## - BP_MagicSlime_Inhibitor InitialLifeSpan 30.0
## - BP_MagicSlime_PuddleCluster: Puddle Damage Per Overlap 5.0,
##   PuddleColor {R:0.6035, G:0.0943, B:0.8177},
##   PuddleDecalMaterial M_MagicSlime_Decal (texture NOT recoverable from the
##   cooked graph), PuddleParticleSystem NS_GooSplash_Explosion
## - GA_MagicSlime_GuardKnockdown SlipDuration 10.0 / GE_MagicSlime_Knockdown 10 s
##
## Simplification (documented): the cooked projectile has no serialized
## InitialSpeed on its ProjectileMovementComponent, so no flight speed is
## invented. The thief spawns the puddle at a raycast aim point instead of
## simulating a lobbed projectile.

const PUDDLE_RADIUS: float = 2.0 # 200 cm
const PUDDLE_LIFETIME: float = 30.0 # Inhibitor InitialLifeSpan 30.0
const PUDDLE_COLOR: Color = Color(0.6035, 0.0943, 0.8177)
const PUDDLE_DAMAGE: float = 5.0 # Puddle Damage Per Overlap
const INHIBITOR_RADIUS: float = 1.5 # InhibitableActorSearchRadius 150 cm
const INHIBITOR_LIFESPAN: float = 30.0
const SLIP_KNOCKDOWN_DURATION: float = 10.0 # SlipDuration / GE 10 s

var radius: float = PUDDLE_RADIUS
var lifetime: float = PUDDLE_LIFETIME
var ttl: float = PUDDLE_LIFETIME
var light_probe: Node = null
var inhibited_count: int = 0

var _start_sec: float = 0.0
var _built: bool = false
var _hit_ids: Dictionary = {}


func _ready() -> void:
	_build()


func setup(pos: Vector3, probe: Node, now_sec: float) -> int:
	global_position = pos
	light_probe = probe
	_start_sec = now_sec
	_build()
	inhibited_count = 0
	if light_probe != null and light_probe.has_method("short_circuit_lights"):
		inhibited_count = int(light_probe.call("short_circuit_lights", pos, INHIBITOR_RADIUS, INHIBITOR_LIFESPAN, now_sec))
	return inhibited_count


func _build() -> void:
	if _built:
		return
	_built = true
	collision_layer = 0
	collision_mask = 1 | 2 | 4
	monitoring = true
	monitorable = false
	var col := CollisionShape3D.new()
	col.name = "PuddleOverlap"
	var sph := SphereShape3D.new()
	sph.radius = PUDDLE_RADIUS
	col.shape = sph
	add_child(col)
	# Flat solid-colour decal derived from the real PuddleColor. The cooked
	# M_MagicSlime_Decal texture is NOT recoverable, so no texture is faked.
	var decal := MeshInstance3D.new()
	decal.name = "PuddleDecal"
	var disc := CylinderMesh.new()
	disc.top_radius = PUDDLE_RADIUS
	disc.bottom_radius = PUDDLE_RADIUS
	disc.height = 0.02
	disc.radial_segments = 32
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(PUDDLE_COLOR.r, PUDDLE_COLOR.g, PUDDLE_COLOR.b, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = PUDDLE_COLOR
	mat.emission_energy_multiplier = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material = mat
	decal.mesh = disc
	decal.position = Vector3(0, 0.03, 0)
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(decal)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	ttl -= delta
	if ttl <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	var iid: int = body.get_instance_id()
	if _hit_ids.has(iid):
		return
	_hit_ids[iid] = true
	if body.is_in_group("guards") or body.has_method("play_slip"):
		# knock_out first: play_slip() forces KO visuals but keeps the
		# default (long) duration if the guard is not already KO, and
		# knock_out() early-returns once KO. KO(10.0) then slip anim = the
		# real 10 s GA_MagicSlime_GuardKnockdown behaviour.
		if body.has_method("knock_out"):
			body.call("knock_out", SLIP_KNOCKDOWN_DURATION)
		if body.has_method("play_slip"):
			body.call("play_slip")
	elif body.has_method("take_damage"):
		body.take_damage(PUDDLE_DAMAGE)
	# NOTE (documented skip): no slippery locomotion effect is applied to the
	# player — there is no cooked source for a friction/slide value, so none
	# is invented.
