extends Node3D
## Authored ward zone (BP_WardZone_Blocker_C / BP_WardZone_Slow_C).
##
## ZoneSize is authored in cooked UE centimetres with X = width, Y = depth and
## Z = height; the runtime box is (X, Z, Y) / 100 with its centre at
## (0, Z/200, 0), i.e. the authored volume sits on the actor origin and rises
## to Z cm. Blocker: StaticBody3D on bit 4 (value 16), the first free layer
## above world/player/guard/civilian; only the thief's mask gains it, so guards
## and civilians keep walking through. Slow: Area3D on the player mask.
##
## Every authored ward has WardInitiallyActive=false, so nothing activates on
## spawn. A linked plate/beam calls activate_from(); a ward with no authored
## inbound link stays inactive by design.
##
## Visual (P1-W, V6-04, KF28): a blocker ward draws the authored
## `SM_BlockerWard_4m_A/B` / `8m_A/B/C` shard cluster. Those meshes were
## previously dropped by the loader's "blocker" name filter, so the flat
## `tat_ward` BoxMesh was the only visual. The level loader now spawns them in
## the `ward_shards` group and the device layer hands each ward its own cluster
## (same one-visual contract as the beam cards). The ward shows the shards only
## while active. A detached/synthetic ward (suites, FTUE without a loaded
## level) falls back to a procedural crystal-shard cluster built from the same
## authored zone size; the flat pane is gone. Slow wards keep a low-alpha
## veil: their authored visual is the translucent MI_WardZone_Slow glyph quad
## (alpha 0.015 in the cooked material) plus the NS_WardZone_Shards Niagara.

signal ward_activated(source: Node)
signal ward_triggered(source: Node, body: Node)
signal power_state_changed(on: bool)
signal ward_shattered(source: Node)

const Geometry := preload("res://src/devices/device_geometry.gd")
const WARD_SHADER: Shader = preload("res://src/core/tat_ward.gdshader")
const WARD_SHARD_SHADER: Shader = preload("res://src/core/tat_ward_shard.gdshader")

## Dedicated collision bit (bit 4, value 16). Player mask = 1 | 4 | 16.
const WARD_BLOCKER_LAYER: int = 16
const PLAYER_LAYER: int = 2
## Authored active tint: BP_WardZone_Base.WardColor #FF4DFD. The per-instance
## dynamic material saved in the level is #7DFFB2 (green); the reference KF28
## ward is purple, so the active look uses the base colour (APPROX_COLOR,
## HARD_LIMIT: the cooked activation colour change is not in the dump).
const WARD_ACTIVE_COLOR: Color = Color(1.0, 77.0 / 255.0, 253.0 / 255.0, 1.0)
const WARD_IDLE_COLOR: Color = Color(125.0 / 255.0, 1.0, 178.0 / 255.0, 1.0)
## Fallback cluster reference size (the authored 3.94 m zone height / 1.65 m
## depth); the procedural cluster scales with the configured zone.
const FALLBACK_REF_SIZE: Vector2 = Vector2(3.94, 1.65)
const FALLBACK_SHARDS: int = 7

var device_id: String = ""
var family: String = "ward_blocker"
var mode: String = "blocker"
var params: Dictionary = {}
var zone_size_m: Vector3 = Vector3(0.3, 3.5, 1.0)
var zone_center_m: Vector3 = Vector3(0.0, 1.75, 0.0)
var initially_active: bool = false
var slow_multiplier: float = 0.25
var slow_seconds: float = 6.0
var magic_damage: float = 50.0
var immunity_seconds: float = 1.0

var player: Node3D = null
var action_targets: Array = []
var active: bool = false
var shattered: bool = false
var awake: bool = true
var applied_count: int = 0
var damage_applied: int = 0
var blocker_body: StaticBody3D = null
var slow_area: Area3D = null
var power_source: Node = null
var power_required: bool = false
## Authored shard nodes adopted from the loaded level (one visual only).
var authored_shards: Array[Node3D] = []

var _powered: bool = true
var _visual: Node3D = null
var _fallback_cluster: Node3D = null
var _veil: MeshInstance3D = null
var _shard_material: ShaderMaterial = null
var _immunity: float = 0.0
var _inside: bool = false
var _built: bool = false

## Authored crystal material shared by every shard: authored base tint plus the
## documented emissive energy. Built once per process.
static var _shared_shard_material: ShaderMaterial = null


func configure(rec: Dictionary, family_defaults: Dictionary, difficulty_value: int = -1) -> void:
	device_id = str(rec.get("id", ""))
	family = str(rec.get("family", "ward_blocker"))
	mode = "blocker" if family == "ward_blocker" else "slow"
	var params_v: Variant = rec.get("params", {})
	params = params_v as Dictionary if params_v is Dictionary else {}
	var defaults: Dictionary = family_defaults.get(family, {}) as Dictionary
	var metric: Dictionary = defaults.get("metric", {}) as Dictionary
	initially_active = bool(metric.get("initially_active", false))
	if params.has("WardInitiallyActive"):
		initially_active = bool(params.get("WardInitiallyActive"))
	slow_multiplier = float(metric.get("slow_multiplier", 0.25))
	slow_seconds = float(metric.get("slow_seconds", 6.0))
	magic_damage = float(metric.get("magic_damage", 50.0))
	immunity_seconds = float(metric.get("immunity_seconds", 1.0))
	var x_cm: float = 0.0
	var y_cm: float = 0.0
	var z_cm: float = 0.0
	var zone_v: Variant = params.get("ZoneSize", null)
	if zone_v is Dictionary:
		var zone: Dictionary = zone_v as Dictionary
		x_cm = float(zone.get("X", 30.0))
		y_cm = float(zone.get("Y", 100.0))
		z_cm = float(zone.get("Z", 350.0))
	else:
		var default_m_v: Variant = metric.get("zone_size_m_default", [0.3, 1.0, 3.5])
		var default_m: Array = default_m_v as Array if default_m_v is Array else [0.3, 1.0, 3.5]
		x_cm = float(default_m[0]) / Geometry.CM_TO_M if default_m.size() > 0 else 30.0
		y_cm = float(default_m[1]) / Geometry.CM_TO_M if default_m.size() > 1 else 100.0
		z_cm = float(default_m[2]) / Geometry.CM_TO_M if default_m.size() > 2 else 350.0
	zone_size_m = Vector3(x_cm, z_cm, y_cm) * Geometry.CM_TO_M
	zone_center_m = Vector3(0.0, z_cm * 0.005, 0.0)
	active = initially_active
	if _built:
		_apply_geometry()
	else:
		_build()
	if active:
		_apply_active()


func _ready() -> void:
	add_to_group("devices")
	add_to_group("ward_zone")
	add_to_group("device_action")
	_build()
	if active:
		_apply_active()


func _build() -> void:
	if _built:
		return
	_built = true
	if mode == "blocker":
		blocker_body = StaticBody3D.new()
		blocker_body.name = "WardBlocker"
		blocker_body.collision_layer = 0
		blocker_body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.name = "WardBox"
		var box := BoxShape3D.new()
		box.size = zone_size_m
		col.shape = box
		col.position = zone_center_m
		blocker_body.add_child(col)
		add_child(blocker_body)
	else:
		slow_area = Area3D.new()
		slow_area.name = "WardSlowArea"
		slow_area.collision_layer = 0
		slow_area.collision_mask = PLAYER_LAYER
		slow_area.monitoring = false
		slow_area.monitorable = false
		var col := CollisionShape3D.new()
		col.name = "WardBox"
		var box := BoxShape3D.new()
		box.size = zone_size_m
		col.shape = box
		col.position = zone_center_m
		slow_area.add_child(col)
		add_child(slow_area)
	_build_visual()
	_apply_geometry()


func _apply_geometry() -> void:
	var box_size: Vector3 = zone_size_m
	if blocker_body != null:
		var col: CollisionShape3D = blocker_body.get_node_or_null("WardBox") as CollisionShape3D
		if col != null:
			var box: BoxShape3D = col.shape as BoxShape3D
			if box != null:
				box.size = box_size
			col.position = zone_center_m
	if slow_area != null:
		var col2: CollisionShape3D = slow_area.get_node_or_null("WardBox") as CollisionShape3D
		if col2 != null:
			var box2: BoxShape3D = col2.shape as BoxShape3D
			if box2 != null:
				box2.size = box_size
			col2.position = zone_center_m
	if _fallback_cluster != null:
		_fallback_cluster.position = zone_center_m
		_fallback_cluster.scale = Vector3(
			1.0,
			maxf(zone_size_m.y, 0.2) / FALLBACK_REF_SIZE.x,
			maxf(zone_size_m.z, 0.2) / FALLBACK_REF_SIZE.y)
	if _veil != null and _veil.mesh is PlaneMesh:
		var plane: PlaneMesh = _veil.mesh as PlaneMesh
		plane.size = Vector2(maxf(zone_size_m.z, 0.2), maxf(zone_size_m.y, 0.2))
		_veil.position = zone_center_m


## Authored crystal material shared by every shard: authored base tint plus the
## documented emissive energy. Built once per process.
static func shard_material() -> ShaderMaterial:
	if _shared_shard_material == null:
		_shared_shard_material = ShaderMaterial.new()
		_shared_shard_material.shader = WARD_SHARD_SHADER
		_shared_shard_material.set_shader_parameter("ward_color", WARD_ACTIVE_COLOR)
		_shared_shard_material.set_shader_parameter("emissive_energy", 1.0)
	return _shared_shard_material


func _build_visual() -> void:
	if mode == "blocker":
		_build_fallback_cluster()
	else:
		# Slow ward: the authored MI_WardZone_Slow quad is almost transparent
		# (Color.a 0.015); keep a faint faceted veil, never the old solid pane.
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(maxf(zone_size_m.z, 0.2), maxf(zone_size_m.y, 0.2))
		var mat := ShaderMaterial.new()
		mat.shader = WARD_SHADER
		mat.set_shader_parameter("ward_color", Color(0.427, 0.216, 0.596, 0.22))
		mat.set_shader_parameter("energy", 1.0)
		mat.set_shader_parameter("edge_fade", 1.0)
		mat.set_shader_parameter("facet_scale", 3.0)
		_veil = MeshInstance3D.new()
		_veil.name = "WardVeil"
		_veil.mesh = mesh
		_veil.material_override = mat
		_veil.position = zone_center_m
		# The ward zone's thin axis is local X; the veil lies in the local ZY
		# plane (a 90 deg yaw from PlaneMesh's native XY).
		_veil.rotation.y = PI * 0.5
		_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_veil)
		_visual = _veil
		_veil.visible = active


func _build_fallback_cluster() -> void:
	# Deterministic shard layout (seeded by the authored device id) used only
	# when the level did not hand over the authored SM_BlockerWard cluster.
	_fallback_cluster = Node3D.new()
	_fallback_cluster.name = "WardShardCluster"
	add_child(_fallback_cluster)
	var seed: int = 0
	for ch: int in device_id.to_utf8_buffer():
		seed = (seed * 131 + ch) & 0x7FFFFFFF
	var mat: ShaderMaterial = shard_material()
	for i: int in range(FALLBACK_SHARDS):
		var rnd: float = fmod(sin(float(seed + i * 71) * 0.013) * 43758.5453, 1.0)
		if rnd < 0.0:
			rnd += 1.0
		var t: float = float(i) / float(FALLBACK_SHARDS - 1)
		# Authored cluster: 7 shards spread over the 1.65 m door depth, each
		# 2.4-3.9 m tall, 0.25-0.6 m wide, 0.12 m thick, random yaw.
		var shard_mesh: BoxMesh = BoxMesh.new()
		shard_mesh.size = Vector3(0.12, 2.5 + 1.3 * rnd, 0.26 + 0.34 * fmod(rnd * 7.0, 1.0))
		var shard: MeshInstance3D = MeshInstance3D.new()
		shard.name = "WardShard_%d" % i
		shard.mesh = shard_mesh
		shard.material_override = mat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fallback_cluster.add_child(shard)
		shard.position = Vector3((rnd - 0.5) * 0.10, shard_mesh.size.y * 0.5, (t - 0.5) * 1.35)
		shard.rotation = Vector3(0.0, rnd * TAU, (rnd - 0.5) * 0.16)
	_visual = _fallback_cluster
	_visual.visible = active


## Adopt the loaded level's authored shard cluster as this ward's only visual.
## The nodes stay at their authored transforms; their visibility follows the
## ward state. Release hides them again (the loader spawns them hidden).
func adopt_ward_shards(shards: Array) -> void:
	authored_shards.clear()
	for s_v: Variant in shards:
		if s_v is Node3D and is_instance_valid(s_v as Node3D):
			var shard: Node3D = s_v as Node3D
			authored_shards.append(shard)
			shard.visible = active
			if shard is MeshInstance3D:
				(shard as MeshInstance3D).material_override = shard_material()
	if _fallback_cluster != null:
		_fallback_cluster.visible = false
	if _veil != null:
		_veil.visible = false


func release_ward_shards() -> void:
	for shard: Node3D in authored_shards:
		if is_instance_valid(shard):
			shard.visible = false
	authored_shards.clear()
	if _fallback_cluster != null:
		_fallback_cluster.visible = active


func has_authored_shards() -> bool:
	return not authored_shards.is_empty()


func set_player(p: Node3D) -> void:
	player = p


func set_action_targets(targets: Array) -> void:
	action_targets = targets


func set_power_source(src: Node) -> void:
	power_source = src
	if src != null and src.has_signal("powered"):
		if not src.is_connected("powered", Callable(self, "_on_power_changed")):
			src.connect("powered", Callable(self, "_on_power_changed"))
		_powered = bool(src.call("is_powered")) if src.has_method("is_powered") else true
	else:
		_powered = true


func _on_power_changed(on: bool) -> void:
	_powered = on
	power_state_changed.emit(on)


func activate_from(_source: Node = null) -> void:
	activate()


func activate() -> void:
	if active or shattered:
		return
	active = true
	_apply_active()
	ward_activated.emit(self)
	if AudioManager != null and AudioManager.has_method("play_cue"):
		AudioManager.call("play_cue", "ward_activate", global_position)


## Public shatter seam (KF29 G5-04). The barrier collapses: the collision goes
## away, the shards hide, the authored end cue plays. Idempotent.
func shatter(source: Node = null) -> void:
	if shattered:
		return
	shattered = true
	active = false
	if blocker_body != null:
		blocker_body.collision_layer = 0
	if slow_area != null:
		slow_area.monitoring = false
	for shard: Node3D in authored_shards:
		if is_instance_valid(shard):
			shard.visible = false
	if _fallback_cluster != null:
		_fallback_cluster.visible = false
	if _veil != null:
		_veil.visible = false
	if AudioManager != null and AudioManager.has_method("play_cue"):
		AudioManager.call("play_cue", "ward_end", global_position)
	ward_shattered.emit(self if source == null else source)


func _apply_active() -> void:
	if mode == "blocker":
		if blocker_body != null:
			blocker_body.collision_layer = WARD_BLOCKER_LAYER
	else:
		if slow_area != null:
			slow_area.monitoring = true
	for shard: Node3D in authored_shards:
		if is_instance_valid(shard):
			shard.visible = true
	if _fallback_cluster != null:
		# Exactly one visual: the procedural cluster is the detached/synthetic
		# fallback only, never shown beside adopted authored shards.
		_fallback_cluster.visible = authored_shards.is_empty()
	if _veil != null:
		_veil.visible = authored_shards.is_empty()


func can_trigger() -> bool:
	if not active or not awake or shattered:
		return false
	return not power_required or _powered


func set_awake(value: bool) -> void:
	awake = value


func tick(delta: float) -> void:
	if _immunity > 0.0:
		_immunity = maxf(0.0, _immunity - delta)
	if not active or mode != "slow":
		return
	var target: Node3D = _resolve_player()
	if target == null:
		_inside = false
		return
	var inside: bool = _body_inside(target)
	if inside and not _inside:
		_inside = true
		if _immunity <= 0.0:
			_apply_slow(target)
			_immunity = immunity_seconds
	elif not inside:
		_inside = false


func _apply_slow(target: Node3D) -> void:
	applied_count += 1
	ward_triggered.emit(self, target)
	if target.has_method("apply_ward_slow"):
		target.call("apply_ward_slow", slow_multiplier, slow_seconds)
	elif target.get("speed_multiplier") != null:
		target.set("speed_multiplier", slow_multiplier)
	if magic_damage > 0.0 and target.has_method("take_damage"):
		target.call("take_damage", magic_damage)
		damage_applied += 1
	if AudioManager != null and AudioManager.has_method("play_cue"):
		AudioManager.call("play_cue", "ward_hit", global_position)


func _body_inside(target: Node3D) -> bool:
	var body: PackedVector3Array = Geometry.body_segment(target)
	if body.size() < 2:
		return false
	var p0: Vector3 = to_local(body[0])
	var p1: Vector3 = to_local(body[1])
	var half: Vector3 = zone_size_m * 0.5
	var box := AABB(zone_center_m - half, zone_size_m)
	return Geometry.segment_intersects_aabb(p0, p1, box)


func _resolve_player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	if not is_inside_tree():
		return null
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node3D:
		player = found as Node3D
		return player
	return null
