extends CharacterBody3D
## Playable Thief controller (Spider, Chameleon, Moth) with stamina, crouch, lean,
## grapple/disguise/astral abilities, Slithersap, Smoke Bomb, Pickpocket Fairy, and Blackjack.

const VfxManager = preload("res://src/core/vfx_manager.gd")

const STAND_HEAD_HEIGHT: float = 1.55
const CROUCH_HEAD_HEIGHT: float = 0.92
const LEAN_OFFSET: float = 0.45
const LEAN_ROLL: float = 0.14
const LEAN_WALL_CHECK_DIST: float = 0.6

signal health_changed(hp: float, max_hp: float)
signal stamina_changed(stam: float, max_stam: float)
signal disguise_changed(integrity: float, active: bool)
signal thief_vision_toggled(enabled: bool)
signal tool_used(tool_id: String, charges_left: int)
signal interacted(target: Node)
signal downed()

@export var walk_speed: float = 4.2
@export var sprint_speed: float = 6.8
@export var crouch_speed: float = 2.1
@export var jump_velocity: float = 5.2
@export var gravity: float = 18.0
@export var mouse_sens: float = 0.0024

var max_health: float = 300.0
var health: float = 300.0
var max_stamina: float = 260.0
var stamina: float = 260.0
var stamina_regen: float = 12.0

var is_crouching: bool = false
var is_sprinting: bool = false
var lean_dir: float = 0.0
var thief_vision_on: bool = false
var thief_vision: bool = false
const DISGUISE_STEAL_RANGE: float = 2.8
const GRAPPLE_ARRIVE_DIST: float = 1.8
const GRAPPLE_VAULT_Y: float = 6.5
var _bj_punch_tween: Tween = null

# Abilities
var ability_cooldown: float = 0.0
var disguise_active: bool = false
var disguise_integrity: float = 100.0
var is_grappling: bool = false
var grapple_target: Vector3 = Vector3.ZERO
var astral_active: bool = false
var astral_ttl: float = 0.0

# Gadgets
var charges: Dictionary = {
	"slithersap": 3,
	"smoke_bomb": 2,
	"pickpocket_fairy": 2,
}
var noise_timer: float = 0.0

var head: Node3D
var cam: Camera3D
var spring_arm: SpringArm3D
var col_shape: CollisionShape3D
var mesh_root: Node3D
var light_probe: Node
var level_ctrl: Node


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	_apply_tuning()
	_build_body()
	if not OS.has_feature("headless") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_tuning() -> void:
	var diff_x: float = GameState.difficulty_curve_x()
	max_health = GameData.eval_curve("CT_PlayerStats", "BaseHealth", diff_x, 300.0)
	health = max_health
	max_stamina = GameData.eval_curve("CT_PlayerStats", "BaseStamina", diff_x, 260.0)
	stamina = max_stamina
	stamina_regen = GameData.eval_curve("CT_PlayerStats", "BaseStaminaRegenRate", diff_x, 2.0) * 6.0


func _build_body() -> void:
	col_shape = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	col_shape.shape = cap
	col_shape.position = Vector3(0, 0.875, 0)
	add_child(col_shape)

	mesh_root = Node3D.new()
	add_child(mesh_root)
	var glb_path: String = "res://assets/ue/Content/Art/Animation/CivMale/Skin/Common/SK_CivMale_Common_01_Jacket.glb"
	if GameState.thief_id == "chameleon" or GameState.thief_id == "moth":
		glb_path = "res://assets/ue/Content/Art/Animation/CivFemale/Skin/Common/SK_CivFemale_Common_01_Jacket.glb"
	var packed: PackedScene = ResourceLoader.load(glb_path) as PackedScene
	if packed != null:
		var inst: Node = packed.instantiate()
		inst.rotation_degrees.y = 180.0
		mesh_root.add_child(inst)
	else:
		var body_mi: MeshInstance3D = MeshInstance3D.new()
		var body_mesh: CapsuleMesh = CapsuleMesh.new()
		body_mesh.radius = 0.32
		body_mesh.height = 1.65
		body_mi.mesh = body_mesh
		body_mi.position = Vector3(0, 0.85, 0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		match GameState.thief_id:
			"spider": mat.albedo_color = Color(0.18, 0.22, 0.34)
			"chameleon": mat.albedo_color = Color(0.16, 0.32, 0.24)
			_: mat.albedo_color = Color(0.28, 0.2, 0.36)
		body_mi.material_override = mat
		mesh_root.add_child(body_mi)

	mesh_root.visible = false

	head = Node3D.new()
	head.position = Vector3(0, STAND_HEAD_HEIGHT, 0)
	add_child(head)

	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 0.0
	spring_arm.position = Vector3.ZERO
	head.add_child(spring_arm)

	cam = Camera3D.new()
	cam.fov = 78.0
	cam.current = true
	spring_arm.add_child(cam)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.state != "playing":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sens)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * mouse_sens, deg_to_rad(-80), deg_to_rad(80))
	elif event.is_action_pressed("crouch"):
		is_crouching = not is_crouching
		var cap: CapsuleShape3D = col_shape.shape as CapsuleShape3D
		if cap != null:
			cap.height = 1.1 if is_crouching else 1.75
			col_shape.position.y = cap.height * 0.5
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("ability"):
		_trigger_thief_ability()
	elif event.is_action_pressed("tool_1"):
		_use_slithersap()
	elif event.is_action_pressed("tool_2"):
		_use_smoke_bomb()
	elif event.is_action_pressed("tool_3"):
		_use_pickpocket_fairy()
	elif event.is_action_pressed("tool_4") or event.is_action_pressed("primary_action"):
		if GameState.thief_id == "spider":
			var grappled: bool = _try_spider_grapple()
			if not grappled:
				_try_blackjack()
		else:
			_try_blackjack()
	elif event.is_action_pressed("thief_vision"):
		thief_vision = not thief_vision
		thief_vision_on = thief_vision
		thief_vision_toggled.emit(thief_vision)
		_update_thief_vision()


func _physics_process(delta: float) -> void:
	if GameState.state != "playing":
		return
	ability_cooldown = maxf(0.0, ability_cooldown - delta)

	# Smooth crouch camera height interpolation.
	var target_head_h: float = CROUCH_HEAD_HEIGHT if is_crouching else STAND_HEAD_HEIGHT
	head.position.y = lerpf(head.position.y, target_head_h, delta * 10.0)

	# Wall-raycast-clamped Q/R lean.
	var target_lean: float = 0.0
	if Input.is_action_pressed("lean_left"):
		target_lean -= 1.0
	if Input.is_action_pressed("lean_right"):
		target_lean += 1.0
	if target_lean != 0.0:
		target_lean *= _get_lean_wall_factor(signf(target_lean))
	lean_dir = lerpf(lean_dir, target_lean, delta * 10.0)
	head.position.x = lean_dir * LEAN_OFFSET
	head.rotation.z = -lean_dir * LEAN_ROLL

	# Spider grapple pull override (smooth pull toward anchor, vault on arrival/release).
	if is_grappling:
		var wire_speed: float = GameData.eval_curve("CT_Tool_Wire", "WirePullSpeed", 1.0, 16.0)
		if wire_speed <= 0.0:
			wire_speed = 16.0
		var to_anchor: Vector3 = grapple_target - global_position
		var anchor_dist: float = to_anchor.length()
		var released: bool = Input.is_action_just_released("ability") or Input.is_action_just_released("tool_4")
		if anchor_dist < GRAPPLE_ARRIVE_DIST or released:
			is_grappling = false
			var vault_dir: Vector3 = Vector3.ZERO
			if anchor_dist > 0.05:
				vault_dir = to_anchor.normalized()
			velocity = vault_dir * wire_speed * 0.35
			velocity.y = GRAPPLE_VAULT_Y
			move_and_slide()
			return
		else:
			var desired: Vector3 = to_anchor.normalized() * wire_speed
			velocity = velocity.lerp(desired, clampf(delta * 6.0, 0.0, 1.0))
			move_and_slide()
			return

	# Movement & Stamina
	var inp: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish: Vector3 = (transform.basis * Vector3(inp.x, 0.0, inp.y)).normalized()
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and wish.length() > 0.1 and stamina > 2.0

	var speed: float = walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed
		var drain: float = absf(GameData.eval_curve("CT_StaminaSystem", "StaminaPerSecond.Sprint", 1.0, -5.0)) * 3.0
		stamina = maxf(0.0, stamina - drain * delta)
	else:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
	stamina_changed.emit(stamina, max_stamina)

	# Velocity FOV feedback (BP_CameraModifier_VelocityFOV)
	cam.fov = lerpf(cam.fov, 82.0 if is_sprinting else 75.0, delta * 8.0)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	velocity.x = lerpf(velocity.x, wish.x * speed, delta * 14.0)
	velocity.z = lerpf(velocity.z, wish.z * speed, delta * 14.0)
	move_and_slide()

	# Footstep cadence timer while moving on floor.
	var planar_speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar_speed > 0.5:
		noise_timer -= delta
		if noise_timer <= 0.0:
			var loudness: float = 3.5
			if is_crouching:
				loudness = 1.5
			elif is_sprinting:
				loudness = 8.0
			NoiseBus.emit_noise(global_position, loudness, self, "footstep")
			if is_crouching:
				noise_timer = 0.5
			elif is_sprinting:
				noise_timer = 0.28
			else:
				noise_timer = 0.4

	# Chameleon Disguise Integrity drain (faster while sprinting or near guards).
	if disguise_active:
		var drain_rate: float = 6.7
		if is_sprinting:
			drain_rate *= 1.8
		if _is_guard_within(5.0):
			drain_rate *= 2.0
		disguise_integrity = maxf(0.0, disguise_integrity - drain_rate * delta)
		if disguise_integrity <= 0.0:
			disguise_integrity = 0.0
			disguise_active = false
		disguise_changed.emit(disguise_integrity, disguise_active)

	# Light visibility probe
	if light_probe != null and light_probe.has_method("sample_visibility"):
		var excl: Array[RID] = [get_rid()]
		GameState.player_light_visibility = light_probe.sample_visibility(global_position, get_world_3d().direct_space_state, excl)


func _get_lean_wall_factor(side_sign: float) -> float:
	if head == null:
		return 1.0
	if side_sign == 0.0:
		return 1.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var side: Vector3 = global_transform.basis.x.normalized() * side_sign
	var from: Vector3 = head.global_position
	var to: Vector3 = from + side * LEAN_WALL_CHECK_DIST
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	var hit_pos: Vector3 = hit["position"] as Vector3
	var dist: float = from.distance_to(hit_pos)
	return clampf(dist / LEAN_WALL_CHECK_DIST, 0.0, 1.0)


func _is_guard_within(dist_max: float) -> bool:
	var guards: Array[Node] = get_tree().get_nodes_in_group("guards")
	for g: Node in guards:
		if g is Node3D:
			var guard_node: Node3D = g as Node3D
			if global_position.distance_to(guard_node.global_position) <= dist_max:
				return true
	return false


func take_damage(amount: float) -> void:
	if disguise_active:
		disguise_active = false
		disguise_integrity = 0.0
		disguise_changed.emit(0.0, false)
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		downed.emit()


func get_nearest_interactable() -> Node:
	var best: Node = null
	var best_d: float = 3.0
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		if not (node is Node3D):
			continue
		var node3d: Node3D = node as Node3D
		var d: float = global_position.distance_to(node3d.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func get_look_interact_prompt() -> String:
	var ko_guard: Node = _get_nearest_ko_guard()
	if ko_guard != null:
		return "[E] Steal Guard Disguise"
	var n: Node = get_nearest_interactable()
	if n == null:
		return ""
	if n.has_method("get_interact_prompt"):
		return str(n.call("get_interact_prompt"))
	var item_nm: Variant = n.get("item_name")
	if item_nm != null:
		return "[E] Steal %s" % str(item_nm)
	return "[E] Interact"


func _get_nearest_ko_guard() -> Node:
	if GameState.thief_id != "chameleon":
		return null
	var best: Node = null
	var best_d: float = DISGUISE_STEAL_RANGE
	var fwd: Vector3 = Vector3.ZERO
	var has_fwd: bool = cam != null
	if has_fwd:
		fwd = -cam.global_transform.basis.z
	for g: Node in get_tree().get_nodes_in_group("guards"):
		if not (g is Node3D):
			continue
		var guard_node: Node3D = g as Node3D
		var guard_state: int = int(g.get("state"))
		if guard_state != 5:
			continue
		var d: float = global_position.distance_to(guard_node.global_position)
		if d > best_d:
			continue
		if has_fwd:
			var to_guard: Vector3 = (guard_node.global_position - global_position).normalized()
			var flat_fwd: Vector3 = Vector3(fwd.x, 0.0, fwd.z).normalized()
			var flat_to: Vector3 = Vector3(to_guard.x, 0.0, to_guard.z).normalized()
			if flat_fwd.length() > 0.1 and flat_to.length() > 0.1 and flat_fwd.dot(flat_to) < -0.2 and d > 1.2:
				continue
		best_d = d
		best = g
	return best


func _try_steal_disguise(guard: Node) -> bool:
	if guard == null:
		return false
	disguise_active = true
	disguise_integrity = 100.0
	disguise_changed.emit(disguise_integrity, disguise_active)
	NoiseBus.emit_noise(global_position, 3.0, self, "disguise")
	interacted.emit(guard)
	return true


func _try_interact() -> void:
	var ko_guard: Node = _get_nearest_ko_guard()
	if ko_guard != null:
		_try_steal_disguise(ko_guard)
		return
	var best: Node = get_nearest_interactable()
	if best != null and best.has_method("interact"):
		best.interact(self)
		interacted.emit(best)


func _trigger_thief_ability() -> void:
	if ability_cooldown > 0.0:
		return
	match GameState.thief_id:
		"spider":
			_try_spider_grapple()
		"chameleon":
			disguise_active = not disguise_active
			if disguise_active and disguise_integrity <= 1.0:
				disguise_integrity = 100.0
			disguise_changed.emit(disguise_integrity, disguise_active)
			ability_cooldown = 2.0
		"moth":
			astral_active = true
			astral_ttl = 8.0
			ability_cooldown = 12.0
			thief_vision = true
			thief_vision_on = true
			thief_vision_toggled.emit(true)
			_update_thief_vision()


func _try_spider_grapple() -> bool:
	if ability_cooldown > 0.0:
		return is_grappling
	if cam == null:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z
	var to: Vector3 = from + fwd * 26.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit["position"] as Vector3
	grapple_target = hit_pos
	is_grappling = true
	ability_cooldown = GameData.eval_curve("CT_Tool_Wire", "WireCooldownPrimary", 1.0, 10.0) * 0.4
	VfxManager.spawn_grapple_beam(get_parent(), global_position + Vector3.UP * 1.2, grapple_target, 0.45)
	NoiseBus.emit_noise(global_position, 5.0, self, "wire")
	return true


func _use_slithersap() -> void:
	if int(charges.get("slithersap", 0)) <= 0:
		return
	charges["slithersap"] = int(charges.get("slithersap", 0)) - 1
	if light_probe != null and light_probe.has_method("short_circuit_lights"):
		light_probe.short_circuit_lights(global_position, 20.0, 25.0, GameState.elapsed_sec)
	VfxManager.spawn_sap_burst(get_parent(), global_position + (-cam.global_transform.basis.z) * 2.0)
	NoiseBus.emit_noise(global_position, 4.0, self, "slithersap")
	tool_used.emit("slithersap", int(charges.get("slithersap", 0)))


func _use_smoke_bomb() -> void:
	if int(charges.get("smoke_bomb", 0)) <= 0:
		return
	charges["smoke_bomb"] = int(charges.get("smoke_bomb", 0)) - 1
	if level_ctrl != null and level_ctrl.has_method("spawn_smoke"):
		level_ctrl.spawn_smoke(global_position + (-global_transform.basis.z) * 2.5, 6.0, 12.0)
	NoiseBus.emit_noise(global_position, 7.0, self, "smoke")
	tool_used.emit("smoke_bomb", int(charges.get("smoke_bomb", 0)))


func _use_pickpocket_fairy() -> void:
	if int(charges.get("pickpocket_fairy", 0)) <= 0:
		return
	charges["pickpocket_fairy"] = int(charges.get("pickpocket_fairy", 0)) - 1
	var best_loot: Node3D = null
	var best_d: float = 25.0
	for n: Node in get_tree().get_nodes_in_group("loot"):
		if n is Node3D and not n.get_meta("collected", false):
			var loot_node: Node3D = n as Node3D
			var d: float = global_position.distance_to(loot_node.global_position)
			if d < best_d:
				best_d = d
				best_loot = loot_node
	if best_loot != null and best_loot.has_method("interact"):
		VfxManager.spawn_fairy_orb(get_parent(), global_position + Vector3.UP * 1.3, best_loot.global_position)
		NoiseBus.emit_noise(best_loot.global_position, 3.0, self, "fairy")
		best_loot.interact(self)
	tool_used.emit("pickpocket_fairy", int(charges.get("pickpocket_fairy", 0)))


func _try_blackjack() -> void:
	if head != null and cam != null:
		var swing_dir: Vector3 = -cam.global_transform.basis.z
		var swing_pos: Vector3 = head.global_position + swing_dir * 0.7
		VfxManager.spawn_blackjack_swing(get_parent(), swing_pos, swing_dir)
	_play_blackjack_camera_punch()
	var base_dmg: float = GameData.eval_curve("CT_Tool_Blackjack", "Damage", 1.0, 35.0)
	var heavy_dmg: float = GameData.eval_curve("CT_Tool_Blackjack", "BlackjackDamageHeavy", 1.0, 75.0)
	if heavy_dmg <= 0.0:
		heavy_dmg = base_dmg
	for g: Node in get_tree().get_nodes_in_group("guards"):
		if not (g is Node3D):
			continue
		var guard_node: Node3D = g as Node3D
		if global_position.distance_to(guard_node.global_position) > 2.4:
			continue
		if not g.has_method("take_knockout"):
			continue
		var final_dmg: float = heavy_dmg
		var guard_state: int = int(g.get("state"))
		if guard_state == 0 or guard_state == 1:
			var to_player: Vector3 = (global_position - guard_node.global_position).normalized()
			var guard_back: Vector3 = guard_node.global_transform.basis.z.normalized()
			var behind_dot: float = guard_back.dot(to_player)
			if behind_dot > 0.25:
				final_dmg = 999.0
		g.take_knockout(final_dmg)
		GameState.takedowns += 1
		NoiseBus.emit_noise(global_position, 4.5, self, "takedown")
		return


func _play_blackjack_camera_punch() -> void:
	if cam == null:
		return
	if _bj_punch_tween != null and _bj_punch_tween.is_valid():
		_bj_punch_tween.kill()
	var base_pitch: float = cam.rotation.x
	var base_roll: float = cam.rotation.z
	_bj_punch_tween = create_tween()
	_bj_punch_tween.tween_property(cam, "rotation:x", base_pitch + deg_to_rad(-4.0), 0.08)
	_bj_punch_tween.parallel().tween_property(cam, "rotation:z", base_roll + deg_to_rad(2.0), 0.08)
	_bj_punch_tween.tween_property(cam, "rotation:x", base_pitch, 0.14)
	_bj_punch_tween.parallel().tween_property(cam, "rotation:z", base_roll, 0.14)


func _update_thief_vision() -> void:
	thief_vision = thief_vision_on
	for n: Node in get_tree().get_nodes_in_group("thief_vision_highlight"):
		if n.has_method("set_highlighted"):
			n.call("set_highlighted", thief_vision_on)
		elif n.has_method("set_highlight"):
			n.call("set_highlight", thief_vision_on)
